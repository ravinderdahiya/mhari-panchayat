<?php

namespace App\Console\Commands;

use App\Models\Block;
use App\Models\Department;
use App\Models\District;
use App\Models\Panchayat;
use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Imports real Panchayati Raj officials from LGD-code-matched JSON, wiring
 * each one to the routing tier ComplaintController::findResolver() looks up:
 *
 *   BDPO (Block Development & Panchayat Officer) -> role bdpo, block_id
 *   DDPO (District Development & Panchayat Officer) -> role ddpo, district_id
 *   XEN  (Executive Engineer, Panchayati Raj)      -> role xen_pr, district_id
 *   CPLO (village-level functionary, one per Gram Panchayat) -> role cplo, panchayat_id
 *
 * Source file: database/data/haryana_officials.json (built by matching
 * "List of BDPO DDPO XEN.xlsx" / "Total Active CPLO data ....xlsx" rows
 * against database/data/haryana_geography.json's LGD codes - see that file's
 * generation script for what was skipped and why: vacant posts with no name,
 * and a handful of XEN rows whose office string didn't name a district).
 *
 * Gram Sachiv (village-level functionary, often holding several Gram
 * Panchayats under one mobile number) -> role gram_sachiv, panchayat_id,
 * loaded separately from database/data/gram_sachiv_officials.json (built
 * directly from "GramSachivList-*.xlsx", whose PanchayatId column is
 * already the same LGD panchayat code used elsewhere - no geography
 * matching needed). Every panchayat a Gram Sachiv covers goes into the
 * user_panchayats pivot, same idea as user_blocks for BDPO.
 *
 * Accounts are created inactive-for-login (a random, never-shared password) -
 * this only seeds identity + jurisdiction so auto-routing has someone to
 * route to. Getting them an actual login still needs a deliberate invite/
 * password-set flow, which is a separate decision, not part of this import.
 */
class ImportHaryanaOfficials extends Command
{
    protected $signature = 'officials:import-haryana
        {--path= : Optional path to haryana_officials.json}
        {--gram-sachiv-path= : Optional path to gram_sachiv_officials.json}';

    protected $description = 'Import BDPO, DDPO, Executive Engineer, CPLO and Gram Sachiv officials, scoped to their block/district/panchayat';

    public function handle(): int
    {
        $path = $this->option('path') ?: database_path('data/haryana_officials.json');

        if (! is_file($path)) {
            $this->error("Officials file not found: {$path}");

            return self::FAILURE;
        }

        $data = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);

        $gramSachivPath = $this->option('gram-sachiv-path') ?: database_path('data/gram_sachiv_officials.json');
        $gramSachivRows = is_file($gramSachivPath)
            ? json_decode(file_get_contents($gramSachivPath), true, 512, JSON_THROW_ON_ERROR)
            : [];

        $blockIdByCode = Block::query()->pluck('id', 'code');
        $districtIdByCode = District::query()->pluck('id', 'code');
        $panchayats = Panchayat::query()->with('block:id,district_id')->get(['id', 'code', 'block_id'])->keyBy('code');
        $prDepartmentId = Department::query()->where('code', 'PR')->value('id');

        $stats = ['created' => 0, 'updated' => 0, 'skipped' => 0];

        DB::transaction(function () use ($data, $gramSachivRows, $blockIdByCode, $districtIdByCode, $panchayats, $prDepartmentId, &$stats) {
            foreach ($data['bdpo'] ?? [] as $row) {
                $blockId = $blockIdByCode[$row['block_code']] ?? null;
                if (! $blockId) {
                    $stats['skipped']++;
                    continue;
                }
                // Real BDPO data has officials holding "additional charge" of
                // several blocks under one mobile number/account - block_id
                // stays whichever block they were first seen with (their
                // primary post), and every block they cover goes into the
                // user_blocks pivot so findResolver() can match on any of them.
                $user = $this->upsertOfficial($row, 'bdpo', [
                    'block_id' => $blockId,
                    'district_id' => Block::find($blockId)?->district_id,
                    'department_id' => $prDepartmentId,
                ], $stats, preserveBlockId: true);
                $user?->blocks()->syncWithoutDetaching([$blockId]);
            }

            foreach ($data['ddpo'] ?? [] as $row) {
                $districtId = $districtIdByCode[$row['district_code']] ?? null;
                if (! $districtId) {
                    $stats['skipped']++;
                    continue;
                }
                $this->upsertOfficial($row, 'ddpo', [
                    'district_id' => $districtId,
                    'department_id' => $prDepartmentId,
                ], $stats);
            }

            foreach ($data['xen'] ?? [] as $row) {
                $districtId = $districtIdByCode[$row['district_code']] ?? null;
                if (! $districtId) {
                    $stats['skipped']++;
                    continue;
                }
                $this->upsertOfficial($row, 'xen_pr', [
                    'district_id' => $districtId,
                    'department_id' => $prDepartmentId,
                ], $stats);
            }

            foreach ($data['cplo'] ?? [] as $row) {
                $panchayat = $panchayats[$row['panchayat_code']] ?? null;
                if (! $panchayat) {
                    $stats['skipped']++;
                    continue;
                }
                $this->upsertOfficial($row, 'cplo', [
                    'panchayat_id' => $panchayat->id,
                    'block_id' => $panchayat->block_id,
                    'district_id' => $panchayat->block?->district_id,
                    'department_id' => $prDepartmentId,
                ], $stats);
            }

            foreach ($gramSachivRows as $row) {
                $panchayat = $panchayats[$row['panchayat_code']] ?? null;
                if (! $panchayat) {
                    $stats['skipped']++;
                    continue;
                }
                // Same "additional charge" pattern as BDPO/blocks above, but at
                // panchayat granularity - panchayat_id stays whichever panchayat
                // they were first seen with, every panchayat they cover goes
                // into the user_panchayats pivot.
                $user = $this->upsertOfficial($row, 'gram_sachiv', [
                    'panchayat_id' => $panchayat->id,
                    'block_id' => $panchayat->block_id,
                    'district_id' => $panchayat->block?->district_id,
                    'department_id' => $prDepartmentId,
                ], $stats, preservePanchayatId: true);
                $user?->panchayats()->syncWithoutDetaching([$panchayat->id]);
            }
        });

        $this->table(['Result', 'Count'], [
            ['Created', $stats['created']],
            ['Updated', $stats['updated']],
            ['Skipped (no jurisdiction match / no usable identifier)', $stats['skipped']],
        ]);

        return self::SUCCESS;
    }

    private function upsertOfficial(array $row, string $role, array $jurisdiction, array &$stats, bool $preserveBlockId = false, bool $preservePanchayatId = false): ?User
    {
        $username = $this->usernameFor($row);
        if (! $username) {
            $stats['skipped']++;

            return null;
        }

        $existing = User::where('username', $username)->first();
        if ($preserveBlockId && $existing?->block_id) {
            unset($jurisdiction['block_id']);
        }
        if ($preservePanchayatId && $existing?->panchayat_id) {
            unset($jurisdiction['panchayat_id']);
        }

        $user = User::updateOrCreate(['username' => $username], [
            'name' => $row['name'],
            'email' => $row['email'] ?? null ?: null,
            'mobile' => $this->normalizedMobile($row['mobile']),
            'member_id' => $row['member_id'] ?? null,
            'family_id' => $row['family_id'] ?? null,
            'role' => $role,
            'is_active' => true,
            'registration_status' => 'active',
            'password' => $existing?->password ?? Hash::make(Str::random(32)),
            ...$jurisdiction,
        ]);

        $stats[$existing ? 'updated' : 'created']++;

        return $user;
    }

    private function normalizedMobile(?string $mobile): ?string
    {
        if (! $mobile) {
            return null;
        }

        // A few XEN rows list multiple numbers ("9417340787, 7973748814") - keep the first.
        $first = trim(explode(',', $mobile)[0]);
        $digits = preg_replace('/\D/', '', $first);

        return $digits !== '' ? $digits : null;
    }

    private function usernameFor(array $row): ?string
    {
        $mobile = $this->normalizedMobile($row['mobile'] ?? null);
        if ($mobile && strlen($mobile) >= 10) {
            return substr($mobile, -10);
        }

        $email = $row['email'] ?? null;

        return $email ? Str::slug(Str::before($email, '@'), '_') : null;
    }
}
