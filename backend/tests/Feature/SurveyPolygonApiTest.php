<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Application;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Symfony\Component\Process\Process;
use Tests\TestCase;
use Throwable;
use ZipArchive;

// Needs a real PostGIS database (the rest of the suite uses in-memory SQLite,
// which has no geometry support) and, for the shapefile tests, GDAL. Uses the
// `mhari_panchayat_test` Postgres DB (override with TRACKING_TEST_DB_*); the
// tests skip if it is unreachable.
//
// Not wrapped in a transaction on purpose: ogr2ogr talks to Postgres through its
// own connection and must be able to see the rows, so every test cleans up the
// users it created (polygons/attributes cascade).
class SurveyPolygonApiTest extends TestCase
{
    /** @var array<int, int> */
    private array $userIds = [];

    /** @var array<int, string> */
    private array $tempFiles = [];

    public function createApplication(): Application
    {
        $app = parent::createApplication();

        $app['config']->set('database.default', 'pgsql');
        $app['config']->set('database.connections.pgsql.host', env('TRACKING_TEST_DB_HOST', '127.0.0.1'));
        $app['config']->set('database.connections.pgsql.port', env('TRACKING_TEST_DB_PORT', 5432));
        $app['config']->set('database.connections.pgsql.database', env('TRACKING_TEST_DB_DATABASE', 'mhari_panchayat_test'));
        $app['config']->set('database.connections.pgsql.username', env('TRACKING_TEST_DB_USERNAME', 'postgres'));
        $app['config']->set('database.connections.pgsql.password', env('TRACKING_TEST_DB_PASSWORD', '123456'));

        return $app;
    }

    protected function setUp(): void
    {
        try {
            parent::setUp();
            DB::statement('CREATE EXTENSION IF NOT EXISTS postgis');
            $this->ensureSchema();
        } catch (Throwable $e) {
            $this->markTestSkipped('PostGIS test database unavailable: '.$e->getMessage());
        }
    }

    protected function tearDown(): void
    {
        if ($this->userIds) {
            DB::table('users')->whereIn('id', $this->userIds)->delete(); // cascades to polygons + attributes
        }
        foreach ($this->tempFiles as $file) {
            is_dir($file) ? File::deleteDirectory($file) : @unlink($file);
        }

        parent::tearDown();
    }

    // migrate:fresh can't be used on an empty Postgres DB: the Haryana geography
    // fix-up migration needs LGD data from `geography:import-haryana`. Mark it as
    // already run and migrate everything else once.
    private function ensureSchema(): void
    {
        if (Schema::hasTable('survey_polygons') && Schema::hasTable('survey_polygon_attributes')) {
            return;
        }

        if (! Schema::hasTable('migrations')) {
            Artisan::call('migrate:install');
        }
        DB::table('migrations')->insertOrIgnore([
            'migration' => '2026_09_03_150000_fix_indri_block_panchayat_splits',
            'batch' => 1,
        ]);
        Artisan::call('migrate', ['--force' => true]);
    }

    // ------------------------------------------------------------------ helpers

    private function user(): User
    {
        $user = User::factory()->create();
        $this->userIds[] = $user->id;

        return $user;
    }

    /** A ~100 m x 100 m square near Hisar, as recorded points (ring not closed). */
    private function squarePoints(bool $closed = false, float $latShift = 0.0): array
    {
        $coords = [
            [29.1492 + $latShift, 75.7217],
            [29.1492 + $latShift, 75.7227],
            [29.1501 + $latShift, 75.7227],
            [29.1501 + $latShift, 75.7217],
        ];
        if ($closed) {
            $coords[] = $coords[0];
        }

        return $this->toPoints($coords);
    }

    private function toPoints(array $coords): array
    {
        return array_map(fn ($c, $i) => [
            'lat' => $c[0],
            'lng' => $c[1],
            'accuracy' => 5.0,
            'timestamp' => now()->addSeconds($i * 4)->toIso8601String(),
        ], $coords, array_keys($coords));
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'uuid' => (string) Str::uuid(),
            'started_at' => '2026-10-05T10:00:00+05:30',
            'ended_at' => '2026-10-05T10:25:00+05:30',
            'source' => 'online',
            'points' => $this->squarePoints(),
        ], $overrides);
    }

    private function gdal(): void
    {
        $process = new Process([config('survey.gdal.ogrinfo'), '--version']);
        try {
            $process->run();
        } catch (Throwable) {
            $this->markTestSkipped('GDAL (ogrinfo/ogr2ogr) is not available. Set OGR2OGR_BIN / OGRINFO_BIN.');
        }
        if (! $process->isSuccessful()) {
            $this->markTestSkipped('GDAL (ogrinfo/ogr2ogr) is not available. Set OGR2OGR_BIN / OGRINFO_BIN.');
        }
    }

    private function ogrinfo(array $args): string
    {
        $process = new Process([config('survey.gdal.ogrinfo'), ...$args]);
        $process->run();
        $this->assertTrue($process->isSuccessful(), 'ogrinfo failed: '.$process->getErrorOutput());

        return $process->getOutput();
    }

    /** Save a binary response (the exported zip) to a temp file. */
    private function saveDownload($response): string
    {
        $path = sys_get_temp_dir().DIRECTORY_SEPARATOR.'shp_test_'.Str::random(10).'.zip';
        file_put_contents($path, $response->streamedContent());
        $this->tempFiles[] = $path;

        return $path;
    }

    /** Copy a zip, leaving out entries with the given extensions. */
    private function zipWithout(string $source, array $extensions): string
    {
        $in = new ZipArchive;
        $in->open($source);
        $path = sys_get_temp_dir().DIRECTORY_SEPARATOR.'shp_test_'.Str::random(10).'.zip';
        $out = new ZipArchive;
        $out->open($path, ZipArchive::CREATE);
        for ($i = 0; $i < $in->numFiles; $i++) {
            $name = $in->getNameIndex($i);
            if (! in_array(strtolower(pathinfo($name, PATHINFO_EXTENSION)), $extensions, true)) {
                $out->addFromString($name, $in->getFromIndex($i));
            }
        }
        $out->close();
        $in->close();
        $this->tempFiles[] = $path;

        return $path;
    }

    private function upload(string $path)
    {
        return new UploadedFile($path, 'polygons.zip', 'application/zip', null, true);
    }

    // ------------------------------------------------------------ polygon creation

    public function test_valid_polygon_is_saved_with_area_and_perimeter(): void
    {
        $payload = $this->payload();

        $response = $this->actingAs($this->user(), 'sanctum')->postJson('/api/polygons', $payload);

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.type', 'Feature')
            ->assertJsonPath('data.geometry.type', 'Polygon')
            ->assertJsonPath('data.properties.uuid', $payload['uuid'])
            ->assertJsonPath('data.properties.point_count', 4)
            ->assertJsonPath('data.properties.has_data', false)
            ->assertJsonPath('data.properties.track.type', 'LineString');

        // 0.001 deg lng x 0.0009 deg lat at ~29.15N is roughly 97 m x 100 m.
        $this->assertEqualsWithDelta(9700, $response->json('data.properties.area_sqm'), 600);
        $this->assertEqualsWithDelta(395, $response->json('data.properties.perimeter_m'), 25);

        $row = DB::selectOne('select ST_SRID(geom) as srid, ST_IsValid(geom) as valid, ST_GeometryType(track) as t from survey_polygons where uuid = ?', [$payload['uuid']]);
        $this->assertSame(4326, (int) $row->srid);
        $this->assertTrue((bool) $row->valid);
        $this->assertSame('ST_LineString', $row->t);
    }

    public function test_ring_is_closed_automatically(): void
    {
        $user = $this->user();

        $open = $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $this->payload());
        $closed = $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $this->payload([
            'points' => $this->squarePoints(closed: true),
        ]));

        $open->assertCreated();
        $closed->assertCreated();
        $this->assertEqualsWithDelta(
            $closed->json('data.properties.area_sqm'),
            $open->json('data.properties.area_sqm'),
            0.01,
        );

        $ring = $open->json('data.geometry.coordinates.0');
        $this->assertSame($ring[0], $ring[count($ring) - 1]);
    }

    public function test_self_intersecting_input_is_repaired_to_a_valid_polygon(): void
    {
        // Bow-tie: the walk crosses itself, so the raw ring is invalid.
        $bowTie = $this->toPoints([
            [29.1490, 75.7210],
            [29.1500, 75.7220],
            [29.1490, 75.7220],
            [29.1500, 75.7210],
        ]);
        $payload = $this->payload(['points' => $bowTie]);

        $response = $this->actingAs($this->user(), 'sanctum')->postJson('/api/polygons', $payload);

        $response->assertCreated()->assertJsonPath('data.geometry.type', 'Polygon');
        $this->assertGreaterThan(0, $response->json('data.properties.area_sqm'));

        $row = DB::selectOne('select ST_IsValid(geom) as valid, ST_GeometryType(geom) as t from survey_polygons where uuid = ?', [$payload['uuid']]);
        $this->assertTrue((bool) $row->valid);
        $this->assertSame('ST_Polygon', $row->t);
    }

    public function test_fewer_than_three_points_is_rejected(): void
    {
        $response = $this->actingAs($this->user(), 'sanctum')->postJson('/api/polygons', $this->payload([
            'points' => array_slice($this->squarePoints(), 0, 2),
        ]));

        $response->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonValidationErrors(['points']);
    }

    public function test_repeated_and_low_accuracy_points_do_not_count(): void
    {
        $sq = $this->squarePoints();
        $noisy = $sq[2];
        $noisy['accuracy'] = 80.0; // worse than the 30 m threshold
        $noisy['lat'] = 29.2;
        $points = [$sq[0], $sq[0], $sq[1], $noisy, $sq[2], $sq[3]];
        $payload = $this->payload(['points' => $points]);

        $response = $this->actingAs($this->user(), 'sanctum')->postJson('/api/polygons', $payload);

        $response->assertCreated()->assertJsonPath('data.properties.point_count', 4);
        // The raw array is kept exactly as received.
        $raw = json_decode(DB::table('survey_polygons')->where('uuid', $payload['uuid'])->value('raw_points'), true);
        $this->assertCount(6, $raw);
    }

    public function test_collinear_path_with_no_area_is_rejected(): void
    {
        $line = $this->toPoints([
            [29.1490, 75.7210],
            [29.1495, 75.7215],
            [29.1500, 75.7220],
        ]);
        $payload = $this->payload(['points' => $line]);

        $this->actingAs($this->user(), 'sanctum')->postJson('/api/polygons', $payload)
            ->assertStatus(422)
            ->assertJsonPath('success', false);

        $this->assertSame(0, DB::table('survey_polygons')->where('uuid', $payload['uuid'])->count());
    }

    public function test_duplicate_uuid_returns_existing_record(): void
    {
        $user = $this->user();
        $payload = $this->payload();

        $first = $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $payload);
        $second = $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $payload);

        $first->assertCreated();
        $second->assertOk()->assertJsonPath('data.properties.id', $first->json('data.properties.id'));
        $this->assertSame(1, DB::table('survey_polygons')->where('uuid', $payload['uuid'])->count());
    }

    public function test_bulk_sync_reports_created_duplicate_and_failed(): void
    {
        $user = $this->user();
        $existing = $this->payload();
        $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $existing)->assertCreated();

        $fresh = $this->payload([
            'source' => 'offline_sync',
            'attributes' => ['owner_name' => 'रामलाल', 'khasra_no' => '12/3'],
        ]);

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/polygons/bulk', [
            $fresh,                                                     // created (+ attributes)
            $existing,                                                  // duplicate
            $this->payload(['points' => [$this->squarePoints()[0]]]),   // failed (1 point)
        ]);

        $response->assertOk()
            ->assertJsonPath('data.summary', ['created' => 1, 'duplicate' => 1, 'failed' => 1])
            ->assertJsonPath('data.results.0.status', 'created')
            ->assertJsonPath('data.results.0.data.has_data', true)
            ->assertJsonPath('data.results.1.status', 'duplicate')
            ->assertJsonPath('data.results.2.status', 'failed');

        $this->assertSame('offline_sync', DB::table('survey_polygons')->where('uuid', $fresh['uuid'])->value('source'));
    }

    // -------------------------------------------------------------- attributes

    public function test_attributes_can_be_sent_on_create_and_upserted_separately(): void
    {
        $user = $this->user();
        $payload = $this->payload(['attributes' => [
            'owner_name' => 'रामलाल',
            'village' => 'Satrod',
            'seed_variety' => 'PB-1121', // not a fixed column -> extra
        ]]);

        $created = $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $payload)->assertCreated();
        $created->assertJsonPath('data.properties.has_data', true)
            ->assertJsonPath('data.properties.owner_name', 'रामलाल')
            ->assertJsonPath('data.properties.extra.seed_variety', 'PB-1121');

        $id = $created->json('data.properties.id');
        $this->assertSame(1, DB::table('survey_polygon_attributes')->where('polygon_id', $id)->count());

        // Upsert merges: crop is added, owner_name stays, extra keys merge.
        $this->actingAs($user, 'sanctum')->putJson("/api/polygons/{$payload['uuid']}/attributes", [
            'crop' => 'Wheat',
            'extra' => ['irrigation' => 'canal'],
        ])->assertOk()
            ->assertJsonPath('data.owner_name', 'रामलाल')
            ->assertJsonPath('data.crop', 'Wheat')
            ->assertJsonPath('data.extra.seed_variety', 'PB-1121')
            ->assertJsonPath('data.extra.irrigation', 'canal');
        $this->assertSame(1, DB::table('survey_polygon_attributes')->where('polygon_id', $id)->count());

        $this->actingAs($user, 'sanctum')->getJson("/api/polygons/{$payload['uuid']}/attributes")
            ->assertOk()->assertJsonPath('data.village', 'Satrod');

        // Merged into the GeoJSON Feature properties.
        $this->actingAs($user, 'sanctum')->getJson("/api/polygons/{$payload['uuid']}")
            ->assertOk()
            ->assertJsonPath('data.properties.crop', 'Wheat')
            ->assertJsonPath('data.properties.track.type', 'LineString');

        $this->actingAs($user, 'sanctum')->deleteJson("/api/polygons/{$payload['uuid']}/attributes")->assertOk();
        $this->actingAs($user, 'sanctum')->getJson("/api/polygons/{$payload['uuid']}/attributes")
            ->assertOk()->assertJsonPath('data', null);
        $this->assertSame(0, DB::table('survey_polygon_attributes')->where('polygon_id', $id)->count());
    }

    public function test_attributes_are_created_by_put_when_missing_and_validated(): void
    {
        $user = $this->user();
        $payload = $this->payload();
        $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $payload)->assertCreated();

        $this->actingAs($user, 'sanctum')->putJson("/api/polygons/{$payload['uuid']}/attributes", ['owner_name' => 'Asha'])
            ->assertCreated()->assertJsonPath('message', 'Attributes created');

        $this->actingAs($user, 'sanctum')->putJson("/api/polygons/{$payload['uuid']}/attributes", ['mobile' => str_repeat('9', 40)])
            ->assertStatus(422)->assertJsonValidationErrors(['mobile']);
    }

    public function test_list_filters_scoping_geojson_and_delete(): void
    {
        $owner = $this->user();
        $other = $this->user();
        $withData = $this->payload(['attributes' => ['village' => 'Satrod']]);
        $plain = $this->payload(['points' => $this->squarePoints(latShift: 0.01)]);

        $this->actingAs($owner, 'sanctum')->postJson('/api/polygons', $withData)->assertCreated();
        $this->actingAs($owner, 'sanctum')->postJson('/api/polygons', $plain)->assertCreated();

        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons')->assertJsonPath('meta.total', 2);
        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons?has_data=true')
            ->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.uuid', $withData['uuid']);
        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons?has_data=false')
            ->assertJsonPath('meta.total', 1)->assertJsonPath('data.0.uuid', $plain['uuid']);
        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons?village=satrod')->assertJsonPath('meta.total', 1);
        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons?village=nowhere')->assertJsonPath('meta.total', 0);

        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons?bbox=75.72,29.14,75.73,29.1496')
            ->assertJsonPath('meta.total', 1);
        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons?bbox=77,28,78,29')->assertJsonPath('meta.total', 0);
        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons?bbox=nonsense')->assertStatus(422);

        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons/geojson')
            ->assertOk()
            ->assertJsonPath('data.type', 'FeatureCollection')
            ->assertJsonCount(2, 'data.features');

        // Another user sees nothing and cannot read, change or delete it.
        $this->actingAs($other, 'sanctum')->getJson('/api/polygons')->assertJsonPath('meta.total', 0);
        $this->actingAs($other, 'sanctum')->getJson('/api/polygons/'.$withData['uuid'])->assertNotFound();
        $this->actingAs($other, 'sanctum')->putJson("/api/polygons/{$withData['uuid']}/attributes", ['crop' => 'x'])->assertNotFound();
        $this->actingAs($other, 'sanctum')->deleteJson('/api/polygons/'.$withData['uuid'])->assertNotFound();

        $this->actingAs($owner, 'sanctum')->deleteJson('/api/polygons/'.$withData['uuid'])->assertOk();
        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons/'.$withData['uuid'])->assertNotFound();
        $this->assertNotNull(DB::table('survey_polygons')->where('uuid', $withData['uuid'])->value('deleted_at'));
    }

    public function test_requires_authentication(): void
    {
        $this->postJson('/api/polygons', $this->payload())->assertUnauthorized();
        $this->getJson('/api/polygons')->assertUnauthorized();
        $this->getJson('/api/polygons/export/shp')->assertUnauthorized();
        $this->postJson('/api/polygons/import/shp')->assertUnauthorized();
    }

    // --------------------------------------------------------------- shapefile

    public function test_shp_export_produces_a_valid_zip_with_aliased_fields_and_utf8(): void
    {
        $this->gdal();
        $user = $this->user();
        $payload = $this->payload(['attributes' => [
            'owner_name' => 'रामलाल',
            'father_name' => 'Shyam',
            'khasra_no' => '12/3',
            'village' => 'Satrod',
            'remarks' => 'north boundary',
            'seed_variety' => 'PB-1121',
        ]]);
        $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $payload)->assertCreated();

        $response = $this->actingAs($user, 'sanctum')->get('/api/polygons/export/shp');
        $response->assertOk();
        $this->assertStringContainsString('application/zip', $response->headers->get('Content-Type'));
        $zipPath = $this->saveDownload($response);

        $zip = new ZipArchive;
        $this->assertTrue($zip->open($zipPath) === true);
        $names = [];
        for ($i = 0; $i < $zip->numFiles; $i++) {
            $names[] = $zip->getNameIndex($i);
        }
        $zip->close();
        foreach (['polygons.shp', 'polygons.shx', 'polygons.dbf', 'polygons.prj', 'polygons.cpg'] as $expected) {
            $this->assertContains($expected, $names);
        }

        $info = $this->ogrinfo(['-al', '-so', "/vsizip/{$zipPath}/polygons.shp"]);
        $this->assertStringContainsString('Feature Count: 1', $info);
        $this->assertStringContainsString('Polygon', $info);
        foreach (['UUID', 'AREA_SQM', 'PERIM_M', 'OWNER', 'FATHER', 'KHASRA', 'MURABBA', 'VILLAGE', 'EXTRA'] as $field) {
            $this->assertStringContainsString($field.':', $info, "missing field {$field}");
        }

        // Hindi survives (UTF-8 .cpg).
        $features = $this->ogrinfo(['-al', "/vsizip/{$zipPath}/polygons.shp"]);
        $this->assertStringContainsString('रामलाल', $features);
        $this->assertStringContainsString($payload['uuid'], $features);
    }

    public function test_shp_export_is_scoped_to_the_user_and_filterable(): void
    {
        $this->gdal();
        $owner = $this->user();
        $other = $this->user();
        $a = $this->payload(['attributes' => ['village' => 'Satrod']]);
        $b = $this->payload(['points' => $this->squarePoints(latShift: 0.01), 'attributes' => ['village' => 'Hisar']]);
        $c = $this->payload();

        $this->actingAs($owner, 'sanctum')->postJson('/api/polygons', $a)->assertCreated();
        $this->actingAs($owner, 'sanctum')->postJson('/api/polygons', $b)->assertCreated();
        $this->actingAs($other, 'sanctum')->postJson('/api/polygons', $c)->assertCreated();

        $zip = $this->saveDownload($this->actingAs($owner, 'sanctum')->get('/api/polygons/export/shp?village=hisar'));
        $this->assertStringContainsString('Feature Count: 1', $this->ogrinfo(['-al', '-so', "/vsizip/{$zip}/polygons.shp"]));

        $zip = $this->saveDownload($this->actingAs($owner, 'sanctum')->get('/api/polygons/export/shp'));
        $this->assertStringContainsString('Feature Count: 2', $this->ogrinfo(['-al', '-so', "/vsizip/{$zip}/polygons.shp"]));

        // Another user's polygon id is never exported.
        $otherId = DB::table('survey_polygons')->where('uuid', $c['uuid'])->value('id');
        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons/export/shp?ids[]='.$otherId)->assertNotFound();
        $this->actingAs($owner, 'sanctum')->getJson('/api/polygons/export/shp?bbox=oops')->assertStatus(422);
    }

    public function test_shp_round_trip_export_then_import(): void
    {
        $this->gdal();
        $user = $this->user();
        $a = $this->payload(['attributes' => [
            'owner_name' => 'रामलाल', 'khasra_no' => '12/3', 'village' => 'Satrod', 'seed_variety' => 'PB-1121',
        ]]);
        $b = $this->payload(['points' => $this->squarePoints(latShift: 0.01)]);

        $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $a)->assertCreated();
        $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $b)->assertCreated();
        $originalArea = (float) DB::table('survey_polygons')->where('user_id', $user->id)->sum('area_sqm');

        $zip = $this->saveDownload($this->actingAs($user, 'sanctum')->get('/api/polygons/export/shp'));

        $response = $this->actingAs($user, 'sanctum')->post('/api/polygons/import/shp', ['file' => $this->upload($zip)], ['Accept' => 'application/json']);

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.features', 2)
            ->assertJsonPath('data.imported', 2)
            ->assertJsonPath('data.skipped', 0)
            ->assertJsonPath('data.warnings', []);

        $imported = DB::table('survey_polygons')->where('user_id', $user->id)->where('source', 'shp_import');
        $this->assertSame(2, $imported->count());
        $this->assertEqualsWithDelta($originalArea, (float) $imported->sum('area_sqm'), $originalArea * 0.01);

        // Attributes came back through the alias map (UTF-8 intact, extra restored).
        $attr = DB::table('survey_polygon_attributes')
            ->join('survey_polygons', 'survey_polygons.id', '=', 'survey_polygon_attributes.polygon_id')
            ->where('survey_polygons.source', 'shp_import')
            ->where('survey_polygons.user_id', $user->id)
            ->first();
        $this->assertSame('रामलाल', $attr->owner_name);
        $this->assertSame('12/3', $attr->khasra_no);
        $this->assertSame('Satrod', $attr->village);
        $this->assertSame('PB-1121', json_decode($attr->extra, true)['seed_variety']);

        // No staging tables or temp dirs are left behind.
        $this->assertSame(0, DB::table('information_schema.tables')->where('table_name', 'like', 'survey_import_%')->count());
        $this->assertSame([], glob(storage_path('app/'.config('survey.shp.tmp_dir').'/shp_import_*')) ?: []);
    }

    public function test_shp_import_without_prj_warns_and_assumes_wgs84(): void
    {
        $this->gdal();
        $user = $this->user();
        $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $this->payload())->assertCreated();

        $zip = $this->saveDownload($this->actingAs($user, 'sanctum')->get('/api/polygons/export/shp'));
        $stripped = $this->zipWithout($zip, ['prj', 'cpg']);

        $response = $this->actingAs($user, 'sanctum')->post('/api/polygons/import/shp', ['file' => $this->upload($stripped)], ['Accept' => 'application/json']);

        $response->assertCreated()->assertJsonPath('data.imported', 1);
        $this->assertCount(2, $response->json('data.warnings'));
        $this->assertStringContainsString('EPSG:4326', $response->json('data.warnings.0'));
    }

    public function test_shp_import_rejects_incomplete_or_invalid_archives(): void
    {
        $this->gdal();
        $user = $this->user();
        $this->actingAs($user, 'sanctum')->postJson('/api/polygons', $this->payload())->assertCreated();
        $zip = $this->saveDownload($this->actingAs($user, 'sanctum')->get('/api/polygons/export/shp'));

        // Missing .dbf
        $this->actingAs($user, 'sanctum')
            ->post('/api/polygons/import/shp', ['file' => $this->upload($this->zipWithout($zip, ['dbf']))], ['Accept' => 'application/json'])
            ->assertStatus(422)->assertJsonPath('success', false);

        // Not a zip at all
        $txt = sys_get_temp_dir().DIRECTORY_SEPARATOR.'not_a_zip_'.Str::random(8).'.txt';
        file_put_contents($txt, 'hello');
        $this->tempFiles[] = $txt;
        $this->actingAs($user, 'sanctum')
            ->post('/api/polygons/import/shp', ['file' => new UploadedFile($txt, 'x.txt', 'text/plain', null, true)], ['Accept' => 'application/json'])
            ->assertStatus(422)->assertJsonValidationErrors(['file']);

        // Nothing was imported by any of the failed attempts.
        $this->assertSame(0, DB::table('survey_polygons')->where('user_id', $user->id)->where('source', 'shp_import')->count());
    }
}
