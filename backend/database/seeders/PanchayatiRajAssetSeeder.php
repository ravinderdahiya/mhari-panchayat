<?php

namespace Database\Seeders;

use App\Models\AssetType;
use App\Models\Department;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class PanchayatiRajAssetSeeder extends Seeder
{
    public function run(): void
    {
        $department = Department::query()->firstOrCreate(
            ['code' => 'PR'],
            ['name' => 'Panchayati Raj', 'name_hi' => 'पंचायती राज'],
        );

        $sort = (int) AssetType::max('sort_order');

        foreach ($this->assets() as [$name, $nameHi]) {
            $asset = AssetType::query()->firstOrNew(['name' => $name]);
            if (! $asset->exists) {
                $asset->sort_order = ++$sort;
            }
            $asset->fill([
                'name_hi' => $nameHi,
                'icon_key' => $this->iconFor($name),
                'is_active' => true,
            ])->save();
            $asset->departments()->syncWithoutDetaching([$department->id]);
        }
    }

    private function iconFor(string $name): string
    {
        $lower = Str::lower($name);

        return match (true) {
            Str::contains($lower, ['gali', 'road', 'culvert']) => 'alt_route',
            Str::contains($lower, ['bhawan', 'sachivalaya']) => 'domain',
            Str::contains($lower, ['chaupal', 'community center']) => 'forum',
            Str::contains($lower, ['barat ghar', 'marriage hall']) => 'home_work',
            Str::contains($lower, ['anganwadi']) => 'child_care',
            Str::contains($lower, ['library']) => 'local_library',
            Str::contains($lower, ['health center']) => 'local_hospital',
            Str::contains($lower, ['veterinary', 'gaushala', 'cattle']) => 'pets',
            Str::contains($lower, ['talab', 'pond', 'water harvesting', 'tubewell', 'hand pump', 'water tank', 'pipeline', 'ro water']) => 'water_drop',
            Str::contains($lower, ['shamlat', 'grazing', 'charand', 'agricultural land', 'common land']) => 'landscape',
            Str::contains($lower, ['sports ground']) => 'stadium',
            Str::contains($lower, ['open gym', 'park']) => 'park',
            Str::contains($lower, ['shamshan']) => 'local_fire_department',
            Str::contains($lower, ['shop', 'dukaan', 'haat', 'mandi']) => 'business',
            Str::contains($lower, ['solar']) => 'wb_sunny',
            default => 'apartment',
        };
    }

    private function assets(): array
    {
        return [
            // Roads & Drainage
            ['Drainage / Naali', 'नाली'],
            ['Village Internal Road / Gali', 'गली'],
            ['Link Road', 'लिंक रोड'],
            ['Culvert', 'पुलिया'],
            ['Street Light', 'स्ट्रीट लाइट'],

            // Buildings
            ['Panchayat Bhawan', 'पंचायत भवन'],
            ['Gram Sachivalaya', 'ग्राम सचिवालय'],
            ['Community Center / Chaupal', 'सामुदायिक केंद्र / चौपाल'],
            ['Barat Ghar / Marriage Hall', 'बारात घर'],
            ['Anganwadi Kendra', 'आंगनवाड़ी केंद्र'],
            ['Public Library / Reading Room', 'सार्वजनिक पुस्तकालय'],
            ['Sub Health Center', 'उप स्वास्थ्य केंद्र'],
            ['Veterinary Center', 'पशु चिकित्सा केंद्र'],

            // Water Infrastructure
            ['Talab / Pond (Johad)', 'तालाब / जोहड़'],
            ['Water Harvesting Structure', 'जल संचयन संरचना'],
            ['Public Tubewell', 'सार्वजनिक ट्यूबवेल'],
            ['Hand Pump', 'हैंड पंप'],
            ['Water Tank / Storage', 'पानी की टंकी'],
            ['Pipeline / Water Supply Line', 'जलापूर्ति पाइपलाइन'],

            // Sanitation
            ['Public Toilet Complex', 'सार्वजनिक शौचालय'],
            ['Solid Waste Management Site', 'ठोस अपशिष्ट प्रबंधन स्थल'],
            ['Soak Pit', 'सोख पिट'],

            // Land Assets
            ['Shamlat Land', 'शामलात भूमि'],
            ['Grazing Land / Charand', 'चरंद भूमि'],
            ['Panchayat Agricultural Land', 'पंचायत कृषि भूमि'],
            ['Village Common Land', 'ग्राम सामुदायिक भूमि'],

            // Recreation / Public Spaces
            ['Sports Ground', 'खेल का मैदान'],
            ['Open Gym / Park', 'ओपन जिम / पार्क'],
            ['Village Chowk / Plaza', 'गांव चौक'],

            // Cremation / Burial
            ['Shamshan Ghat', 'श्मशान घाट'],
            ['Graveyard / Kabristan', 'कब्रिस्तान'],

            // Commercial / Revenue Assets
            ['Shop / Dukaan (Panchayat-owned)', 'पंचायत दुकान'],
            ['Haat / Mandi Structure', 'हाट / मंडी संरचना'],

            // Livestock
            ['Gaushala / Cattle Shed', 'गौशाला'],

            // Miscellaneous
            ['Boundary Wall', 'चारदीवारी'],
            ['Panchayat Ghar Furniture/Equipment', 'पंचायत घर उपकरण'],
            ['RO Water Plant', 'आरओ वाटर प्लांट'],
            ['Solar Street Light Unit', 'सोलर स्ट्रीट लाइट'],
        ];
    }
}
