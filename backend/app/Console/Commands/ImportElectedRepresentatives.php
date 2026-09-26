<?php

namespace App\Console\Commands;

use App\Models\Block;
use App\Models\District;
use App\Models\ElectedRepresentative;
use App\Models\Panchayat;
use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Imports the Haryana Panchayati Raj "ER-Data.xlsx" workbook (Zila Parishad
 * members, Panchayat Samiti members, Sarpanches, Panches) from its JSON
 * export at database/data/elected_representatives_source.json.
 *
 * ZP / PS / Panches have no login role in this app - they land in the
 * read-only `elected_representatives` directory table, matched to their
 * district/block/panchayat.
 *
 * Sarpanches are the one tier that already has a portal role
 * (App\Enums\Role::Sarpanch, jurisdiction-scoped to panchayat_id - see
 * ComplaintController::JURISDICTION_SCOPE_BY_ROLE), so they're upserted into
 * `users` instead, mirroring officials:import-haryana's pattern: identity +
 * jurisdiction only, inactive-for-login (random password) until a real
 * invite/password-set flow brings them in.
 */
class ImportElectedRepresentatives extends Command
{
    // The Panches sheet spells this district without the 'h' Districts.name
    // uses ("Charkhi Dadri") - every other sheet in the workbook spells it
    // correctly, so this is the one alias the source data needs.
    private const DISTRICT_NAME_ALIASES = [
        'CHARKI DADRI' => 'CHARKHI DADRI',
    ];

    protected $signature = 'er:import
        {--path= : Optional path to elected_representatives_source.json}
        {--only= : Comma-separated subset of tiers to (re)run: zp,ps,panch,sarpanches}';

    protected $description = 'Import ZP/PS/Panches into the elected_representatives directory and Sarpanches as users';

    public function handle(): int
    {
        // ~70k rows across 4 sheets, decoded into memory as one JSON tree -
        // comfortably past the default 128M CLI memory_limit.
        ini_set('memory_limit', '512M');

        $path = $this->option('path') ?: database_path('data/elected_representatives_source.json');

        if (! is_file($path)) {
            $this->error("Source file not found: {$path}");

            return self::FAILURE;
        }

        $data = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);

        $districtIdByName = District::query()->get(['id', 'name'])
            ->mapWithKeys(fn ($d) => [strtoupper($d->name) => $d->id]);

        $blockIdByDistrictAndName = Block::query()->get(['id', 'name', 'district_id'])
            ->mapWithKeys(fn ($b) => [$b->district_id.'|'.strtoupper($b->name) => $b->id]);

        $panchayats = Panchayat::query()->with('block:id,district_id')->get(['id', 'code', 'block_id'])->keyBy('code');

        $only = $this->option('only') ? explode(',', $this->option('only')) : null;
        $shouldRun = fn (string $tier) => $only === null || in_array($tier, $only, true);

        if ($shouldRun('zp')) {
            $this->importDirectoryTier('zp', $data['zp'] ?? [], $districtIdByName, $blockIdByDistrictAndName, $panchayats);
        }
        if ($shouldRun('ps')) {
            $this->importDirectoryTier('ps', $data['ps'] ?? [], $districtIdByName, $blockIdByDistrictAndName, $panchayats);
        }
        if ($shouldRun('panch')) {
            $this->importDirectoryTier('panch', $data['panches'] ?? [], $districtIdByName, $blockIdByDistrictAndName, $panchayats);
        }
        if ($shouldRun('sarpanches')) {
            $this->importSarpanches($data['sarpanches'] ?? [], $panchayats);
        }

        return self::SUCCESS;
    }

    /** @param \Illuminate\Support\Collection<string, int> $districtIdByName */
    /** @param \Illuminate\Support\Collection<string, int> $blockIdByDistrictAndName */
    /** @param \Illuminate\Support\Collection<string, \App\Models\Panchayat> $panchayats */
    private function importDirectoryTier(
        string $tier,
        array $rows,
        $districtIdByName,
        $blockIdByDistrictAndName,
        $panchayats,
    ): void {
        $stats = ['matched' => 0, 'skipped' => 0];
        $batch = [];
        $flush = function () use (&$batch, $tier) {
            if (! $batch) {
                return;
            }
            ElectedRepresentative::query()->upsert(
                $batch,
                ['tier', 'source_sr_no'],
                ['district_id', 'block_id', 'panchayat_id', 'ward_no', 'name', 'father_name', 'mobile', 'gender', 'updated_at'],
            );
            $batch = [];
        };

        foreach ($rows as $row) {
            $districtName = strtoupper((string) $row['district_name']);
            $districtName = self::DISTRICT_NAME_ALIASES[$districtName] ?? $districtName;
            $districtId = $districtIdByName[$districtName] ?? null;
            if (! $districtId) {
                $stats['skipped']++;

                continue;
            }

            $blockId = null;
            $panchayatId = null;

            if (array_key_exists('panchayat_code', $row)) {
                $panchayat = $panchayats[$row['panchayat_code']] ?? null;
                if (! $panchayat) {
                    $stats['skipped']++;

                    continue;
                }
                $panchayatId = $panchayat->id;
                $blockId = $panchayat->block_id;
            } elseif (array_key_exists('block_name', $row)) {
                $blockId = $blockIdByDistrictAndName[$districtId.'|'.strtoupper((string) $row['block_name'])] ?? null;
                if (! $blockId) {
                    $stats['skipped']++;

                    continue;
                }
            }

            $stats['matched']++;
            $batch[] = [
                'tier' => $tier,
                'district_id' => $districtId,
                'block_id' => $blockId,
                'panchayat_id' => $panchayatId,
                'ward_no' => $row['ward_no'] ?? null,
                'name' => $row['name'],
                'father_name' => $row['father_name'] ?? null,
                'mobile' => $row['mobile'] ?? null,
                'gender' => $row['gender'] ?? null,
                'source_sr_no' => $row['sr_no'],
                'created_at' => now(),
                'updated_at' => now(),
            ];

            if (count($batch) >= 1000) {
                $flush();
            }
        }
        $flush();

        $this->info("{$tier}: {$stats['matched']} imported, {$stats['skipped']} skipped (no jurisdiction match)");
    }

    /** @param \Illuminate\Support\Collection<string, \App\Models\Panchayat> $panchayats */
    private function importSarpanches(array $rows, $panchayats): void
    {
        $stats = ['created' => 0, 'updated' => 0, 'skipped' => 0];

        DB::transaction(function () use ($rows, $panchayats, &$stats) {
            foreach ($rows as $row) {
                $panchayat = $panchayats[$row['panchayat_code']] ?? null;
                if (! $panchayat || ! $row['name'] || ! $row['mobile']) {
                    $stats['skipped']++;

                    continue;
                }

                $username = $this->usernameFor($row['mobile']);
                if (! $username) {
                    $stats['skipped']++;

                    continue;
                }

                $existing = User::where('username', $username)->first();

                User::updateOrCreate(['username' => $username], [
                    'name' => $row['name'],
                    'mobile' => $row['mobile'],
                    'role' => 'sarpanch',
                    'panchayat_id' => $panchayat->id,
                    'block_id' => $panchayat->block_id,
                    'district_id' => $panchayat->block?->district_id,
                    'is_active' => true,
                    'registration_status' => 'active',
                    'password' => $existing?->password ?? Hash::make(Str::random(32)),
                ]);

                $stats[$existing ? 'updated' : 'created']++;
            }
        });

        $this->table(['Sarpanches', 'Count'], [
            ['Created', $stats['created']],
            ['Updated', $stats['updated']],
            ['Skipped (no panchayat match / missing name or mobile)', $stats['skipped']],
        ]);
    }

    private function usernameFor(?string $mobile): ?string
    {
        if (! $mobile || strlen($mobile) < 10) {
            return null;
        }

        return substr($mobile, -10);
    }
}
