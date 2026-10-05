<?php

namespace App\Services;

use App\Exceptions\PolygonException;
use App\Models\SurveyPolygon;
use App\Models\SurveyPolygonAttribute;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Str;
use Symfony\Component\Process\Process;
use Throwable;
use ZipArchive;

// ESRI Shapefile export/import for survey polygons through GDAL's ogr2ogr.
//
// Safety notes:
//  - ogr2ogr is started with an argument array (no shell), so nothing is parsed
//    by a shell. Paths and names come from us; user input never reaches a command.
//  - The export SQL given to ogr2ogr only contains integer ids that were resolved
//    with bound parameters and scoped to the user beforehand.
//  - The DB password is passed through PGPASSWORD, not on the command line.
class ShapefileService
{
    private const ALLOWED_EXT = ['shp', 'shx', 'dbf', 'prj', 'cpg'];

    // ------------------------------------------------------------------ export

    /**
     * Build a zipped shapefile of the user's polygons (geometry + attributes joined).
     *
     * @param  array<int, int>  $ids
     * @param  array{0: float, 1: float, 2: float, 3: float}|null  $bbox
     * @return string absolute path of the zip (caller deletes it after sending)
     */
    public function export(User $user, array $ids, ?array $bbox, ?string $village): string
    {
        $ids = $this->resolveExportIds($user, $ids, $bbox, $village);

        $dir = $this->makeTempDir('shp_export_');
        try {
            $sqlPath = $dir.DIRECTORY_SEPARATOR.'query.sql';
            file_put_contents($sqlPath, $this->exportSql($ids));

            $outDir = $dir.DIRECTORY_SEPARATOR.'out';
            mkdir($outDir);

            $this->run([
                config('survey.gdal.ogr2ogr'),
                '-f', 'ESRI Shapefile',
                $outDir.DIRECTORY_SEPARATOR.'polygons.shp',
                'PG:'.$this->pgConnection(),
                '-sql', '@'.$sqlPath,
                '-nln', 'polygons',
                '-nlt', 'POLYGON',
                '-t_srs', 'EPSG:4326',
                '-lco', 'ENCODING=UTF-8', // keeps Hindi text intact; writes the .cpg
            ], 'Shapefile export failed');

            $zipPath = storage_path('app/'.config('survey.shp.tmp_dir').'/polygons_'.Str::random(16).'.zip');
            $zip = new ZipArchive;
            if ($zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
                throw new PolygonException('Could not create the zip file.', [], 500);
            }
            foreach (self::ALLOWED_EXT as $ext) {
                $file = $outDir.DIRECTORY_SEPARATOR.'polygons.'.$ext;
                if (is_file($file)) {
                    $zip->addFile($file, 'polygons.'.$ext);
                }
            }
            $zip->close();

            return $zipPath;
        } finally {
            File::deleteDirectory($dir);
        }
    }

    /** @return array<int, int> */
    private function resolveExportIds(User $user, array $ids, ?array $bbox, ?string $village): array
    {
        $max = (int) config('survey.shp.max_export');

        $query = SurveyPolygon::query()->summary()->where('survey_polygons.user_id', $user->id);
        if ($ids) {
            $query->whereIn('survey_polygons.id', array_map('intval', $ids));
        }
        if ($bbox) {
            $query->intersectsBbox(...$bbox);
        }
        if ($village !== null && $village !== '') {
            $query->whereHas('attribute', fn ($q) => $q->whereRaw('lower(village) = lower(?)', [$village]));
        }

        $found = $query->orderBy('survey_polygons.id')->limit($max + 1)->pluck('survey_polygons.id')->map(fn ($v) => (int) $v)->all();

        if ($found === []) {
            throw new PolygonException('No polygons match the given filters.', [], 404);
        }
        if (count($found) > $max) {
            throw new PolygonException("Too many polygons to export at once (max {$max}). Narrow the filter.", [], 422);
        }

        return $found;
    }

    // Shapefile field names are limited to 10 chars, so every column gets an
    // explicit alias from config/survey.php. Text is cut to the DBF 254 limit.
    private function exportSql(array $ids): string
    {
        $cols = ['p.geom AS geom'];
        foreach (config('survey.shp_polygon_aliases') as $column => $alias) {
            $expr = match ($column) {
                'uuid' => 'p.uuid::text',
                'description' => 'left(p.description, 254)',
                default => 'p.'.$column,
            };
            $cols[] = $expr.' AS "'.$alias.'"';
        }
        foreach (config('survey.shp_aliases') as $column => $alias) {
            $cols[] = 'a.'.$column.'::varchar(254) AS "'.$alias.'"';
        }
        $cols[] = 'left(a.extra::text, 254) AS "'.config('survey.shp_extra_alias').'"';

        return 'SELECT '.implode(', ', $cols)
            .' FROM survey_polygons p LEFT JOIN survey_polygon_attributes a ON a.polygon_id = p.id'
            .' WHERE p.deleted_at IS NULL AND p.id IN ('.implode(',', array_map('intval', $ids)).')'
            .' ORDER BY p.id';
    }

    // ------------------------------------------------------------------ import

    /**
     * Import a zipped shapefile into survey_polygons (+ attributes).
     *
     * @return array{features: int, imported: int, skipped: int, skipped_details: array<int, array<string, mixed>>, warnings: array<int, string>}
     */
    public function import(User $user, UploadedFile $zipFile): array
    {
        $warnings = [];
        $dir = $this->makeTempDir('shp_import_');
        $staging = 'survey_import_'.bin2hex(random_bytes(6));

        try {
            $shpPath = $this->extractZip($zipFile, $dir, $hasPrj, $hasCpg);

            if (! $hasPrj) {
                $warnings[] = 'No .prj file found - coordinates were assumed to be EPSG:4326 (WGS84).';
            }
            if (! $hasCpg) {
                $warnings[] = 'No .cpg file found - attribute text was assumed to be UTF-8.';
            }

            $this->loadIntoStaging($shpPath, $staging, $hasPrj, $hasCpg);

            return $this->importFromStaging($user, $staging, $warnings);
        } finally {
            // Always: staging table (name is generated above and re-validated) and temp files.
            if (preg_match('/^survey_import_[0-9a-f]{12}$/', $staging)) {
                try {
                    DB::statement('DROP TABLE IF EXISTS "'.$staging.'"');
                } catch (Throwable $e) {
                    report($e);
                }
            }
            File::deleteDirectory($dir);
        }
    }

    // Validates the archive, then writes only the allowed files under fixed names
    // (upload.shp, upload.dbf ...) so entry names never touch the filesystem.
    private function extractZip(UploadedFile $file, string $dir, ?bool &$hasPrj, ?bool &$hasCpg): string
    {
        $zip = new ZipArchive;
        if ($zip->open($file->getRealPath()) !== true) {
            throw new PolygonException('The uploaded file is not a valid zip archive.', ['file' => ['Invalid zip archive.']]);
        }

        try {
            $maxBytes = (int) config('survey.shp.max_unzipped_mb') * 1024 * 1024;
            $total = 0;
            $entries = []; // lower-case stem => [ext => index]

            for ($i = 0; $i < $zip->numFiles; $i++) {
                $stat = $zip->statIndex($i);
                $name = str_replace('\\', '/', $stat['name']);
                if (str_ends_with($name, '/') || str_starts_with(basename($name), '.') || str_contains($name, '__MACOSX')) {
                    continue;
                }

                $total += $stat['size'];
                if ($total > $maxBytes) {
                    throw new PolygonException('The archive is too large once extracted.', ['file' => ['Archive exceeds the allowed unzipped size.']]);
                }

                $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
                if (! in_array($ext, self::ALLOWED_EXT, true)) {
                    continue;
                }
                $stem = strtolower(pathinfo($name, PATHINFO_FILENAME));
                $entries[$stem][$ext] = $i;
            }

            $layers = array_filter($entries, fn ($e) => isset($e['shp']));
            if (count($layers) === 0) {
                throw new PolygonException('The zip does not contain a .shp file.', ['file' => ['Missing .shp file.']]);
            }
            if (count($layers) > 1) {
                throw new PolygonException('The zip contains more than one shapefile; upload one layer at a time.', ['file' => ['Multiple .shp files found.']]);
            }

            $parts = reset($layers);
            foreach (['shx', 'dbf'] as $required) {
                if (! isset($parts[$required])) {
                    throw new PolygonException("The shapefile is incomplete: missing .{$required} file.", ['file' => ["Missing .{$required} file."]]);
                }
            }

            foreach ($parts as $ext => $index) {
                $in = $zip->getStream($zip->getNameIndex($index));
                $out = fopen($dir.DIRECTORY_SEPARATOR.'upload.'.$ext, 'wb');
                if (! $in || ! $out) {
                    throw new PolygonException('Could not read the archive.', [], 500);
                }
                stream_copy_to_stream($in, $out);
                fclose($in);
                fclose($out);
            }

            $hasPrj = isset($parts['prj']);
            $hasCpg = isset($parts['cpg']);

            return $dir.DIRECTORY_SEPARATOR.'upload.shp';
        } finally {
            $zip->close();
        }
    }

    private function loadIntoStaging(string $shpPath, string $staging, bool $hasPrj, bool $hasCpg): void
    {
        $args = [
            config('survey.gdal.ogr2ogr'),
            '-f', 'PostgreSQL',
            'PG:'.$this->pgConnection(),
            $shpPath,
            '-nln', $staging,
            '-nlt', 'PROMOTE_TO_MULTI',
            '-lco', 'GEOMETRY_NAME=geom',
            '-lco', 'FID=ogc_fid',
            '-lco', 'PRECISION=NO',
            '-lco', 'SPATIAL_INDEX=NONE',
            '-lco', 'SCHEMA=public',
            '-overwrite',
        ];
        // With a .prj: reproject to 4326. Without: assume the data already is 4326.
        array_push($args, ...($hasPrj ? ['-t_srs', 'EPSG:4326'] : ['-a_srs', 'EPSG:4326']));
        if (! $hasCpg) {
            array_push($args, '-oo', 'ENCODING=UTF-8');
        }

        $this->run($args, 'Could not read the shapefile');
    }

    /**
     * @param  array<int, string>  $warnings
     * @return array{features: int, imported: int, skipped: int, skipped_details: array<int, array<string, mixed>>, warnings: array<int, string>}
     */
    private function importFromStaging(User $user, string $staging, array $warnings): array
    {
        $table = '"'.$staging.'"'; // $staging is generated by us (hex), see import()

        $count = (int) DB::selectOne("SELECT count(*) AS c FROM {$table}")->c;
        $maxFeatures = (int) config('survey.shp.max_features');
        if ($count > $maxFeatures) {
            throw new PolygonException("The shapefile has {$count} features; the limit is {$maxFeatures}.", ['file' => ['Too many features.']]);
        }

        $features = DB::select("SELECT ogc_fid, to_jsonb(s) - 'geom' - 'ogc_fid' AS props FROM {$table} s ORDER BY ogc_fid");
        $reverse = $this->reverseAliasMap();
        $minArea = (float) config('tracking.min_area_sqm');

        // MakeValid -> keep polygon parts -> explode MultiPolygons into rows. The
        // range check is a MATERIALIZED step so geography casts never see bad coordinates.
        $insertSql = <<<SQL
            WITH parts AS MATERIALIZED (
                SELECT (ST_Dump(ST_CollectionExtract(ST_MakeValid(ST_Force2D(geom)), 3))).geom AS g
                FROM {$table} WHERE ogc_fid = ?
            ),
            ok AS MATERIALIZED (
                SELECT g FROM parts
                WHERE NOT ST_IsEmpty(g)
                  AND ST_XMin(g) >= -180 AND ST_XMax(g) <= 180 AND ST_YMin(g) >= -90 AND ST_YMax(g) <= 90
            )
            INSERT INTO survey_polygons
                (uuid, user_id, description, geom, track, raw_points, area_sqm, perimeter_m, point_count, source, created_at, updated_at)
            SELECT gen_random_uuid(), ?::bigint, ?::varchar, g, NULL, NULL,
                   ST_Area(g::geography), ST_Perimeter(g::geography), ST_NPoints(g), 'shp_import', now(), now()
            FROM ok WHERE ST_Area(g::geography) >= ?::float8
            RETURNING id
            SQL;

        $imported = 0;
        $skipped = [];

        DB::transaction(function () use ($features, $insertSql, $user, $minArea, $reverse, &$imported, &$skipped) {
            foreach ($features as $feature) {
                $props = json_decode($feature->props, true) ?: [];
                $description = $this->descriptionFrom($props);
                $ids = array_map(fn ($r) => (int) $r->id, DB::select($insertSql, [$feature->ogc_fid, $user->id, $description, $minArea]));

                if ($ids === []) {
                    $skipped[] = ['feature' => (int) $feature->ogc_fid, 'reason' => 'Empty, non-polygon, out-of-range or zero-area geometry'];

                    continue;
                }

                $attributes = $this->mapProps($props, $reverse);
                foreach ($ids as $id) {
                    $imported++;
                    if ($attributes) {
                        SurveyPolygonAttribute::upsertFor($id, $attributes);
                    }
                }
            }
        });

        return [
            'features' => count($features),
            'imported' => $imported,
            'skipped' => count($skipped),
            'skipped_details' => array_slice($skipped, 0, 50),
            'warnings' => $warnings,
        ];
    }

    /** The polygon description from the DBF (alias DESCRIP), cut to the column size. */
    private function descriptionFrom(array $props): ?string
    {
        $alias = strtolower(config('survey.shp_polygon_aliases.description'));
        foreach ($props as $field => $value) {
            if (strtolower((string) $field) === $alias && is_string($value) && trim($value) !== '') {
                return mb_substr(trim($value), 0, 500);
            }
        }

        return null;
    }

    /** lower-case DBF field => attribute column (null = derived/ignored). */
    private function reverseAliasMap(): array
    {
        $map = [];
        foreach (config('survey.shp_aliases') as $column => $alias) {
            $map[strtolower($alias)] = $column;
            $map[strtolower($column)] = $column; // field names that already fit in 10 chars
        }
        foreach (config('survey.shp_polygon_aliases') as $alias) {
            $map[strtolower($alias)] = null;
        }
        $map[strtolower(config('survey.shp_extra_alias'))] = 'extra';

        return $map;
    }

    /**
     * DBF properties -> attribute payload (fixed columns, the rest under extra).
     * Returns [] when the feature carries no data at all.
     *
     * @param  array<string, mixed>  $props
     * @param  array<string, string|null>  $reverse
     * @return array<string, mixed>
     */
    private function mapProps(array $props, array $reverse): array
    {
        $out = [];
        $extra = [];

        foreach ($props as $field => $value) {
            if (is_string($value)) {
                $value = trim($value);
            }
            if ($value === null || $value === '') {
                continue;
            }

            $key = strtolower((string) $field);
            if (array_key_exists($key, $reverse)) {
                $column = $reverse[$key];
                if ($column === null) {
                    continue; // uuid / area / perimeter are derived
                }
                if ($column === 'extra') {
                    $decoded = is_string($value) ? json_decode($value, true) : null;
                    if (is_array($decoded)) {
                        $extra = array_merge($extra, $decoded);
                    }

                    continue;
                }
                $out[$column] = is_scalar($value) ? (string) $value : null;
            } else {
                $extra[$key] = $value;
            }
        }

        if ($extra) {
            $out['extra'] = $extra;
        }

        return $out;
    }

    // --------------------------------------------------------------- plumbing

    /** @param array<int, string> $command */
    private function run(array $command, string $failureMessage): void
    {
        $conn = config('database.connections.'.config('database.default'));

        $env = [
            'PGPASSWORD' => (string) ($conn['password'] ?? ''),
            'PGCLIENTENCODING' => 'UTF8',
        ];
        if ($dir = config('survey.gdal.data_dir')) {
            $env['GDAL_DATA'] = $dir;
        }
        if ($dir = config('survey.gdal.proj_dir')) {
            $env['PROJ_LIB'] = $dir;
            $env['PROJ_DATA'] = $dir;
        }

        $process = new Process($command, null, $env);
        $process->setTimeout((float) config('survey.gdal.timeout'));

        try {
            $process->run();
        } catch (Throwable $e) {
            report($e);
            throw new PolygonException($failureMessage.': GDAL (ogr2ogr) could not be started or timed out.', [], 500);
        }

        if (! $process->isSuccessful()) {
            $stderr = trim($process->getErrorOutput() ?: $process->getOutput());
            report(new \RuntimeException($failureMessage.': '.$stderr));
            // The first line of GDAL's message is useful to the caller and holds no secrets.
            $first = Str::limit(strtok($stderr, "\n") ?: 'unknown error', 300);
            throw new PolygonException($failureMessage.': '.$first, [], 422);
        }
    }

    // libpq key=value connection string without the password.
    private function pgConnection(): string
    {
        $c = config('database.connections.'.config('database.default'));
        $quote = fn ($v) => "'".str_replace(['\\', "'"], ['\\\\', "\\'"], (string) $v)."'";

        return implode(' ', [
            'host='.$quote($c['host'] ?? '127.0.0.1'),
            'port='.$quote($c['port'] ?? 5432),
            'dbname='.$quote($c['database']),
            'user='.$quote($c['username']),
        ]);
    }

    private function makeTempDir(string $prefix): string
    {
        $base = storage_path('app/'.config('survey.shp.tmp_dir'));
        File::ensureDirectoryExists($base);

        $dir = $base.DIRECTORY_SEPARATOR.$prefix.Str::random(16);
        mkdir($dir, 0700);

        return $dir;
    }
}
