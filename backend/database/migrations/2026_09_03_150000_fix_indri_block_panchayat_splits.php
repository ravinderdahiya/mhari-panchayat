<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Haryana_Hierarchy_Master.xlsx (LGD source of truth) splits 3 panchayats
 * under Indri block (code 7101, Nuh district) that our earlier seed had
 * merged into their neighbors:
 *   - village 63083 "Kiranj(187)" belongs to panchayat 265249 "Kiranj Patti
 *     Jattan", not 29416 "Kiranj"
 *   - village 63087 "Indri(197)" belongs to panchayat 298025 "Nawabgarh",
 *     not 29395 "Indri"
 *   - village 63138 "Sudaka (145)" belongs to panchayat 29441 "Sudaka", not
 *     298024 "Machrauli" - this panchayat has a CPLO (Rounaq Ali) in the
 *     master file who was never imported because the panchayat didn't exist
 *
 * Verified before writing this: none of the 3 target villages/panchayats
 * are referenced by any complaint, user, or asset survey, so the reassign
 * is safe.
 */
return new class extends Migration
{
    private const SPLITS = [
        ['panchayat_code' => '265249', 'panchayat_name' => 'Kiranj Patti Jattan', 'village_code' => '63083'],
        ['panchayat_code' => '298025', 'panchayat_name' => 'Nawabgarh', 'village_code' => '63087'],
        ['panchayat_code' => '29441', 'panchayat_name' => 'Sudaka', 'village_code' => '63138'],
    ];

    private const INDRI_BLOCK_CODE = '7101';

    public function up(): void
    {
        DB::transaction(function () {
            $blockId = DB::table('blocks')->where('code', self::INDRI_BLOCK_CODE)->value('id');

            foreach (self::SPLITS as $split) {
                $panchayatId = DB::table('panchayats')->where('code', $split['panchayat_code'])->value('id');

                if (! $panchayatId) {
                    $panchayatId = DB::table('panchayats')->insertGetId([
                        'name' => $split['panchayat_name'],
                        'code' => $split['panchayat_code'],
                        'block_id' => $blockId,
                        'is_active' => true,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }

                DB::table('villages')->where('code', $split['village_code'])->update([
                    'panchayat_id' => $panchayatId,
                    'updated_at' => now(),
                ]);
            }

            DB::table('users')->updateOrInsert(
                ['username' => '9991061548'],
                [
                    'name' => 'ROUNAQ ALI',
                    'mobile' => '9991061548',
                    'email' => 'billaddin5480@gmail.com',
                    'role' => 'cplo',
                    'panchayat_id' => DB::table('panchayats')->where('code', '29441')->value('id'),
                    'block_id' => $blockId,
                    'district_id' => DB::table('blocks')->where('id', $blockId)->value('district_id'),
                    'is_active' => true,
                    'registration_status' => 'active',
                    'password' => bcrypt(\Illuminate\Support\Str::random(32)),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]
            );
        });
    }

    public function down(): void
    {
        DB::transaction(function () {
            $oldPanchayatByVillage = [
                '63083' => '29416',   // Kiranj
                '63087' => '29395',   // Indri
                '63138' => '298024',  // Machrauli
            ];

            foreach ($oldPanchayatByVillage as $villageCode => $panchayatCode) {
                $panchayatId = DB::table('panchayats')->where('code', $panchayatCode)->value('id');
                DB::table('villages')->where('code', $villageCode)->update([
                    'panchayat_id' => $panchayatId,
                    'updated_at' => now(),
                ]);
            }

            DB::table('users')->where('username', '9991061548')->delete();

            foreach (array_column(self::SPLITS, 'panchayat_code') as $code) {
                DB::table('panchayats')->where('code', $code)->delete();
            }
        });
    }
};
