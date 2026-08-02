<?php

namespace App\Console\Commands;

use App\Models\Block;
use App\Models\District;
use App\Models\Panchayat;
use App\Models\State;
use App\Models\Tehsil;
use App\Models\Village;
use App\Models\VillageAsset;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Imports Haryana admin hierarchy from LGD-derived JSON:
 * State → District → Tehsil / Block → Gram Panchayat → Village
 *
 * Source file: database/data/haryana_geography.json
 * (built from https://lgdirectory.gov.in via ramSeraph/opendata dumps)
 */
class ImportHaryanaGeography extends Command
{
    protected $signature = 'geography:import-haryana
                            {--path= : Optional path to haryana_geography.json}
                            {--keep-assets : Keep existing village_assets rows (will fail if village ids change)}';

    protected $description = 'Import full Haryana districts, tehsils, blocks, gram panchayats and villages';

    public function handle(): int
    {
        $path = $this->option('path')
            ?: database_path('data/haryana_geography.json');

        if (! is_file($path)) {
            $this->error("Geography file not found: {$path}");

            return self::FAILURE;
        }

        $this->info("Loading {$path} …");
        $data = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);

        $districtRows = $data['districts'] ?? [];
        $tehsilRows = $data['tehsils'] ?? [];
        $blockRows = $data['blocks'] ?? [];
        $panchayatRows = $data['panchayats'] ?? [];
        $villageRows = $data['villages'] ?? [];

        $this->table(['Entity', 'Rows in file'], [
            ['Districts', count($districtRows)],
            ['Tehsils', count($tehsilRows)],
            ['Blocks', count($blockRows)],
            ['Panchayats', count($panchayatRows)],
            ['Villages', count($villageRows)],
        ]);

        DB::transaction(function () use (
            $data,
            $districtRows,
            $tehsilRows,
            $blockRows,
            $panchayatRows,
            $villageRows,
        ) {
            if (! $this->option('keep-assets')) {
                VillageAsset::query()->delete();
            }

            // Child tables first — demo / partial hierarchy is replaced wholesale.
            Village::query()->delete();
            Panchayat::query()->delete();
            Block::query()->delete();
            Tehsil::query()->delete();

            $stateMeta = $data['state'] ?? ['name' => 'Haryana', 'code' => '6'];
            $state = State::query()->firstOrCreate(
                ['name' => $stateMeta['name']],
                ['code' => (string) ($stateMeta['code'] ?? 'HR')],
            );
            $state->update(['code' => (string) ($stateMeta['code'] ?? $state->code)]);

            $districtIdByCode = [];
            foreach ($districtRows as $row) {
                $code = (string) $row['code'];
                $name = trim((string) $row['name']);

                $district = District::query()
                    ->where('state_id', $state->id)
                    ->where(function ($q) use ($name, $code) {
                        $q->where('name', $name)->orWhere('code', $code);
                    })
                    ->first();

                if ($district) {
                    $district->update(['name' => $name, 'code' => $code, 'state_id' => $state->id]);
                } else {
                    $district = District::query()->create([
                        'name' => $name,
                        'code' => $code,
                        'state_id' => $state->id,
                    ]);
                }

                $districtIdByCode[$code] = $district->id;
            }

            $this->info('Districts upserted: '.count($districtIdByCode));

            $tehsilInsert = [];
            $now = now();
            foreach ($tehsilRows as $row) {
                $districtId = $districtIdByCode[(string) $row['district_code']] ?? null;
                if (! $districtId) {
                    continue;
                }
                $tehsilInsert[] = [
                    'name' => trim((string) $row['name']),
                    'code' => (string) $row['code'],
                    'district_id' => $districtId,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }
            foreach (array_chunk($tehsilInsert, 500) as $chunk) {
                Tehsil::query()->insert($chunk);
            }
            $tehsilIdByCode = [];
            Tehsil::query()->select(['id', 'code'])->orderBy('id')->chunkById(500, function ($rows) use (&$tehsilIdByCode) {
                foreach ($rows as $row) {
                    $tehsilIdByCode[(string) $row->code] = $row->id;
                }
            });
            $this->info('Tehsils inserted: '.count($tehsilInsert));

            $blockIdByCode = [];
            foreach ($blockRows as $row) {
                $districtId = $districtIdByCode[(string) $row['district_code']] ?? null;
                if (! $districtId) {
                    continue;
                }
                $block = Block::query()->create([
                    'name' => trim((string) $row['name']),
                    'code' => (string) $row['code'],
                    'district_id' => $districtId,
                ]);
                $blockIdByCode[(string) $row['code']] = $block->id;
            }
            $this->info('Blocks inserted: '.count($blockIdByCode));

            $panchayatIdByCode = [];
            $panchayatInsert = [];
            foreach ($panchayatRows as $row) {
                $blockId = $blockIdByCode[(string) $row['block_code']] ?? null;
                if (! $blockId) {
                    continue;
                }
                $panchayatInsert[] = [
                    'name' => trim((string) $row['name']),
                    'code' => (string) $row['code'],
                    'block_id' => $blockId,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }
            foreach (array_chunk($panchayatInsert, 500) as $chunk) {
                Panchayat::query()->insert($chunk);
            }
            // Reload id map (insert does not return ids reliably across drivers).
            Panchayat::query()->select(['id', 'code'])->orderBy('id')->chunkById(1000, function ($rows) use (&$panchayatIdByCode) {
                foreach ($rows as $row) {
                    $panchayatIdByCode[(string) $row->code] = $row->id;
                }
            });
            $this->info('Panchayats inserted: '.count($panchayatIdByCode));

            $villageInsert = [];
            $skipped = 0;
            foreach ($villageRows as $row) {
                $panchayatId = $panchayatIdByCode[(string) $row['panchayat_code']] ?? null;
                if (! $panchayatId) {
                    $skipped++;
                    continue;
                }
                $villageInsert[] = [
                    'name' => trim((string) $row['name']),
                    'code' => (string) $row['code'],
                    'panchayat_id' => $panchayatId,
                    'tehsil_id' => $tehsilIdByCode[(string) ($row['tehsil_code'] ?? '')] ?? null,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }
            foreach (array_chunk($villageInsert, 500) as $chunk) {
                Village::query()->insert($chunk);
            }
            $this->info('Villages inserted: '.count($villageInsert).($skipped ? " (skipped {$skipped})" : ''));
        });

        $this->newLine();
        $this->info('Done. Current DB counts:');
        $this->table(['Entity', 'Count'], [
            ['States', State::query()->count()],
            ['Districts', District::query()->count()],
            ['Tehsils', Tehsil::query()->count()],
            ['Blocks', Block::query()->count()],
            ['Panchayats', Panchayat::query()->count()],
            ['Villages', Village::query()->count()],
        ]);

        return self::SUCCESS;
    }
}
