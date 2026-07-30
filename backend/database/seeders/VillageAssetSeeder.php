<?php

namespace Database\Seeders;

use App\Models\User;
use App\Models\Village;
use App\Models\VillageAsset;
use Illuminate\Database\Seeder;

// Demo data spanning all 3 geometry types and a spread of categories, so the
// Village Assets map/table are populated immediately rather than starting
// empty. Base coordinates sit around Sisana (the one seeded village) in
// Haryana, with small offsets so points/lines/polygons are visibly distinct
// on the map rather than stacked on one spot.
class VillageAssetSeeder extends Seeder
{
    public function run(): void
    {
        $village = Village::first();
        $creator = User::where('username', 'testadmin')->first();

        if (! $village || ! $creator) {
            $this->command?->warn('Skipping VillageAssetSeeder - no village/admin user found yet.');

            return;
        }

        VillageAsset::query()->delete();

        $baseLat = 29.0588;
        $baseLng = 76.0856;

        $points = [
            ['Water Infrastructure', 'Handpumps', 'Handpump - Main Chowk', 0.0021, -0.0032, 'Working', 'Good'],
            ['Water Infrastructure', 'Bore wells', 'Bore Well - Ward 3', -0.0045, 0.0018, 'Working', 'Fair'],
            ['Drainage & Sanitation', 'Public/community toilets', 'Community Toilet - Ward 2', 0.0033, 0.0044, 'Working', 'Good'],
            ['Electricity & Lighting', 'Streetlights/solar lights', 'Solar Light - Bus Stand', -0.0018, -0.0021, 'Not Working', 'Poor'],
            ['Electricity & Lighting', 'Transformers', 'Transformer - Ward 1', 0.0052, -0.0012, 'Working', 'Good'],
            ['Community Buildings', 'Panchayat Ghar/Bhawan', 'Panchayat Bhawan', 0.0, 0.0, 'Working', 'Good'],
            ['Community Buildings', 'Anganwadi centres', 'Anganwadi Kendra - Ward 4', 0.0061, 0.0028, 'Working', 'Fair'],
            ['Community Buildings', 'Primary/secondary schools', 'Govt Primary School', -0.0031, 0.0055, 'Working', 'Good'],
            ['Community Buildings', 'Health sub-centre/PHC', 'Health Sub-Centre', 0.0019, 0.0067, 'Under Construction', 'Fair'],
            ['Religious & Public Places', 'Temples/Mandir', 'Shiv Mandir', -0.0027, -0.0044, 'Working', 'Good'],
            ['Agriculture-related Assets', 'Grain storage/godowns', 'Grain Godown', 0.0074, -0.0038, 'Working', 'Good'],
            ['Waste Management', 'Garbage collection points', 'Garbage Point - Ward 5', -0.0052, 0.0031, 'Working', 'Fair'],
        ];

        foreach ($points as [$category, $subtype, $name, $dLat, $dLng, $status, $condition]) {
            VillageAsset::create([
                'village_id' => $village->id,
                'category' => $category,
                'subtype' => $subtype,
                'asset_name' => $name,
                'geometry_type' => 'Point',
                'latitude' => $baseLat + $dLat,
                'longitude' => $baseLng + $dLng,
                'status' => $status,
                'condition' => $condition,
                'ward_no' => rand(1, 6),
                'installed_date' => now()->subYears(rand(1, 8))->subDays(rand(0, 300)),
                'remarks' => null,
                'created_by' => $creator->id,
            ]);
        }

        $lines = [
            ['Roads & Connectivity', 'Village link roads (Gram Sadak)', 'Main Link Road', [
                [$baseLat - 0.006, $baseLng - 0.006],
                [$baseLat - 0.002, $baseLng - 0.002],
                [$baseLat + 0.002, $baseLng + 0.001],
                [$baseLat + 0.006, $baseLng + 0.005],
            ], 'Working', 'Fair'],
            ['Roads & Connectivity', 'Internal streets/gallies', 'Ward 3 Gali', [
                [$baseLat + 0.001, $baseLng - 0.004],
                [$baseLat + 0.003, $baseLng - 0.001],
                [$baseLat + 0.004, $baseLng + 0.002],
            ], 'Working', 'Good'],
            ['Drainage & Sanitation', 'Drains (pucca/kaccha)', 'Main Drain - Ward 2', [
                [$baseLat - 0.003, $baseLng + 0.002],
                [$baseLat - 0.001, $baseLng + 0.004],
                [$baseLat + 0.002, $baseLng + 0.006],
            ], 'Not Working', 'Poor'],
            ['Water Infrastructure', 'Canals/Nehar', 'Minor Canal', [
                [$baseLat - 0.007, $baseLng + 0.001],
                [$baseLat - 0.004, $baseLng + 0.004],
                [$baseLat - 0.001, $baseLng + 0.007],
            ], 'Working', 'Good'],
        ];

        foreach ($lines as [$category, $subtype, $name, $path, $status, $condition]) {
            VillageAsset::create([
                'village_id' => $village->id,
                'category' => $category,
                'subtype' => $subtype,
                'asset_name' => $name,
                'geometry_type' => 'Line',
                'path' => $path,
                'status' => $status,
                'condition' => $condition,
                'ward_no' => rand(1, 6),
                'installed_date' => now()->subYears(rand(1, 10)),
                'remarks' => null,
                'created_by' => $creator->id,
            ]);
        }

        $polygons = [
            ['Water Infrastructure', 'Ponds/Talab', 'Village Talab', [
                [$baseLat + 0.007, $baseLng - 0.007],
                [$baseLat + 0.008, $baseLng - 0.005],
                [$baseLat + 0.0075, $baseLng - 0.003],
                [$baseLat + 0.0065, $baseLng - 0.005],
            ], 'Working', 'Fair'],
            ['Recreation & Sports', 'Playgrounds', 'Village Playground', [
                [$baseLat - 0.008, $baseLng - 0.002],
                [$baseLat - 0.0075, $baseLng + 0.001],
                [$baseLat - 0.0085, $baseLng + 0.003],
                [$baseLat - 0.009, $baseLng + 0.0],
            ], 'Working', 'Good'],
            ['Boundary & Administrative', 'Village boundary', 'Sisana Village Boundary', [
                [$baseLat - 0.01, $baseLng - 0.01],
                [$baseLat + 0.01, $baseLng - 0.01],
                [$baseLat + 0.01, $baseLng + 0.01],
                [$baseLat - 0.01, $baseLng + 0.01],
            ], 'Working', 'Good'],
            ['Agriculture-related Assets', 'Common land (Shamlat)', 'Shamlat Land - Ward 6', [
                [$baseLat + 0.003, $baseLng - 0.009],
                [$baseLat + 0.005, $baseLng - 0.007],
                [$baseLat + 0.004, $baseLng - 0.005],
            ], 'Working', 'Fair'],
        ];

        foreach ($polygons as [$category, $subtype, $name, $path, $status, $condition]) {
            VillageAsset::create([
                'village_id' => $village->id,
                'category' => $category,
                'subtype' => $subtype,
                'asset_name' => $name,
                'geometry_type' => 'Polygon',
                'path' => $path,
                'status' => $status,
                'condition' => $condition,
                'ward_no' => rand(1, 6),
                'installed_date' => now()->subYears(rand(2, 15)),
                'remarks' => null,
                'created_by' => $creator->id,
            ]);
        }

        $this->command?->info('Seeded '.VillageAsset::count().' village assets.');
    }
}
