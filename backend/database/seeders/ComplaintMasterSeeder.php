<?php

namespace Database\Seeders;

use App\Models\AssetType;
use App\Models\ComplaintCategory;
use App\Models\ComplaintPriority;
use App\Models\Department;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class ComplaintMasterSeeder extends Seeder
{
    public function run(): void
    {
        $priorities = collect([
            'low' => ['Low', 1],
            'medium' => ['Medium', 2],
            'high' => ['High', 3],
            'urgent' => ['Urgent', 4],
        ])->mapWithKeys(function (array $definition, string $key) {
            $priority = ComplaintPriority::updateOrCreate(
                ['name' => $definition[0]],
                ['level' => $definition[1]],
            );

            return [$key => $priority];
        });

        $departments = [
            'PHED' => ['Public Health Engineering', '\u091c\u0928 \u0938\u094d\u0935\u093e\u0938\u094d\u0925\u094d\u092f \u0905\u092d\u093f\u092f\u093e\u0902\u0924\u094d\u0930\u093f\u0915\u0940'],
            'PWD' => ['Public Works Department', '\u0932\u094b\u0915 \u0928\u093f\u0930\u094d\u092e\u093e\u0923 \u0935\u093f\u092d\u093e\u0917'],
            'UHBVN' => ['Electricity Department', '\u092c\u093f\u091c\u0932\u0940 \u0935\u093f\u092d\u093e\u0917 (UHBVN)'],
            'PR' => ['Panchayati Raj', '\u092a\u0902\u091a\u093e\u092f\u0924\u0940 \u0930\u093e\u091c'],
            'SBM' => ['Swachh Bharat Mission', '\u0938\u094d\u0935\u091a\u094d\u091b \u092d\u093e\u0930\u0924 \u092e\u093f\u0936\u0928'],
            'HEALTH' => ['Health Department', '\u0938\u094d\u0935\u093e\u0938\u094d\u0925\u094d\u092f \u0935\u093f\u092d\u093e\u0917'],
            'EDU' => ['Education Department', '\u0936\u093f\u0915\u094d\u0937\u093e \u0935\u093f\u092d\u093e\u0917'],
            'IRR' => ['Irrigation Department', '\u0938\u093f\u0902\u091a\u093e\u0908 \u0935\u093f\u092d\u093e\u0917'],
            'AGRI' => ['Agriculture Department', '\u0915\u0943\u0937\u093f \u0935\u093f\u092d\u093e\u0917'],
            'AH' => ['Animal Husbandry Department', '\u092a\u0936\u0941\u092a\u093e\u0932\u0928 \u0935\u093f\u092d\u093e\u0917'],
            'WCD' => ['Women & Child Development', '\u092e\u0939\u093f\u0932\u093e \u090f\u0935\u0902 \u092c\u093e\u0932 \u0935\u093f\u0915\u093e\u0938'],
        ];

        $catalog = $this->catalog();
        $assetSort = (int) AssetType::max('sort_order');
        $categorySort = (int) ComplaintCategory::max('sort_order');

        foreach ($departments as $code => [$name, $nameHi]) {
            $department = Department::query()->where('code', $code)->first();
            if (! $department && $code === 'AH') {
                $department = Department::query()->where('code', 'AHD')->first();
            }
            $department ??= Department::query()->where('name', $name)->first();
            $department ??= new Department();
            $department->fill([
                'name' => $name,
                'name_hi' => $this->unicode($nameHi),
                'code' => $code,
            ])->save();

            foreach ($catalog[$code]['assets'] as [$assetName, $assetNameHi]) {
                $asset = AssetType::query()->firstOrNew(['name' => $assetName]);
                if (! $asset->exists) {
                    $asset->sort_order = ++$assetSort;
                }
                $asset->fill([
                    'name_hi' => $this->unicode($assetNameHi),
                    'icon_key' => $this->iconFor($assetName),
                    'is_active' => true,
                ])->save();
                $asset->departments()->syncWithoutDetaching([$department->id]);

                foreach ($catalog[$code]['categories'] as [$categoryName, $categoryNameHi, $priorityKey]) {
                    $category = ComplaintCategory::query()->where([
                        'department_id' => $department->id,
                        'asset_type_id' => $asset->id,
                        'name' => $categoryName,
                    ])->first();
                    $category ??= ComplaintCategory::query()
                        ->whereNull('department_id')
                        ->where('asset_type_id', $asset->id)
                        ->where('name', $categoryName)
                        ->where('code', 'like', $code.'-%')
                        ->first();
                    $category ??= new ComplaintCategory();
                    if (! $category->exists) {
                        $category->sort_order = ++$categorySort;
                    }
                    $category->fill([
                        'department_id' => $department->id,
                        'asset_type_id' => $asset->id,
                        'name' => $categoryName,
                        'name_hi' => $this->unicode($categoryNameHi),
                        'code' => $this->categoryCode($code, $assetName, $categoryName),
                        'parent_id' => null,
                        'district_id' => null,
                        'default_priority_id' => $priorities[$priorityKey]->id,
                    ])->save();
                }
            }
        }
    }

    private function unicode(string $escaped): string
    {
        return json_decode('"'.$escaped.'"', true, 512, JSON_THROW_ON_ERROR);
    }

    private function categoryCode(string $department, string $asset, string $category): string
    {
        return Str::limit(Str::upper($department.'-'.Str::slug($asset).'-'.Str::slug($category)), 190, '');
    }

    private function iconFor(string $asset): string
    {
        $name = Str::lower($asset);

        return match (true) {
            Str::contains($name, ['water', 'pump', 'tap', 'canal', 'tubewell']) => 'water_drop',
            Str::contains($name, ['road', 'bridge']) => 'route',
            Str::contains($name, ['light', 'electric', 'transformer', 'power']) => 'electric_bolt',
            Str::contains($name, ['toilet', 'garbage', 'sewage', 'drainage']) => 'cleaning_services',
            Str::contains($name, ['school', 'anganwadi']) => 'school',
            Str::contains($name, ['health', 'hospital', 'ambulance']) => 'local_hospital',
            default => 'apartment',
        };
    }

    private function catalog(): array
    {
        return [
            'PHED' => [
                'assets' => [
                    ['Hand Pump', '\u0939\u0948\u0902\u0921 \u092a\u0902\u092a'],
                    ['Water Pipeline', '\u092a\u093e\u0928\u0940 \u0915\u0940 \u092a\u093e\u0907\u092a\u0932\u093e\u0907\u0928'],
                    ['Water Tank / Tanki', '\u092a\u093e\u0928\u0940 \u0915\u0940 \u091f\u0902\u0915\u0940'],
                    ['Water Tap Connection', '\u0928\u0932 \u0915\u0928\u0947\u0915\u094d\u0936\u0928'],
                ],
                'categories' => [
                    ['No Water Supply', '\u092a\u093e\u0928\u0940 \u0915\u0940 \u0906\u092a\u0942\u0930\u094d\u0924\u093f \u0928\u0939\u0940\u0902', 'urgent'],
                    ['Low Water Pressure', '\u0915\u092e \u092a\u093e\u0928\u0940 \u0915\u093e \u0926\u092c\u093e\u0935', 'medium'],
                    ['Water Leakage', '\u092a\u093e\u0928\u0940 \u0915\u093e \u0930\u093f\u0938\u093e\u0935', 'high'],
                    ['Contaminated / Dirty Water', '\u0917\u0902\u0926\u093e \u092a\u093e\u0928\u0940', 'urgent'],
                    ['Pipeline Damaged', '\u092a\u093e\u0907\u092a\u0932\u093e\u0907\u0928 \u0915\u094d\u0937\u0924\u093f\u0917\u094d\u0930\u0938\u094d\u0924', 'high'],
                    ['Hand Pump Not Working', '\u0939\u0948\u0902\u0921 \u092a\u0902\u092a \u0916\u0930\u093e\u092c', 'high'],
                ],
            ],
            'PWD' => [
                'assets' => [
                    ['Road', '\u0938\u0921\u093c\u0915'],
                    ['Bridge / Culvert', '\u092a\u0941\u0932 / \u092a\u0941\u0932\u093f\u092f\u093e'],
                    ['Government Building', '\u0938\u0930\u0915\u093e\u0930\u0940 \u092d\u0935\u0928'],
                ],
                'categories' => [
                    ['Pothole', '\u0917\u0921\u094d\u0922\u093e', 'high'],
                    ['Road Damaged / Broken', '\u0938\u0921\u093c\u0915 \u091f\u0942\u091f\u0940 \u0939\u0941\u0908', 'high'],
                    ['Road Not Constructed', '\u0938\u0921\u093c\u0915 \u0915\u093e \u0928\u093f\u0930\u094d\u092e\u093e\u0923 \u0928\u0939\u0940\u0902 \u0939\u0941\u0906', 'medium'],
                    ['Encroachment on Road', '\u0938\u0921\u093c\u0915 \u092a\u0930 \u0905\u0924\u093f\u0915\u094d\u0930\u092e\u0923', 'medium'],
                    ['Bridge/Culvert Damaged', '\u092a\u0941\u0932/\u092a\u0941\u0932\u093f\u092f\u093e \u0915\u094d\u0937\u0924\u093f\u0917\u094d\u0930\u0938\u094d\u0924', 'urgent'],
                    ['Building Maintenance Needed', '\u092d\u0935\u0928 \u092e\u0930\u092e\u094d\u092e\u0924 \u0906\u0935\u0936\u094d\u092f\u0915', 'low'],
                ],
            ],
            'UHBVN' => [
                'assets' => [
                    ['Street Light', '\u0938\u094d\u091f\u094d\u0930\u0940\u091f \u0932\u093e\u0907\u091f'],
                    ['Electric Pole', '\u092c\u093f\u091c\u0932\u0940 \u0915\u093e \u0916\u0902\u092d\u093e'],
                    ['Transformer', '\u091f\u094d\u0930\u093e\u0902\u0938\u092b\u093e\u0930\u094d\u092e\u0930'],
                    ['Power Line / Wire', '\u092c\u093f\u091c\u0932\u0940 \u0915\u0940 \u0924\u093e\u0930'],
                ],
                'categories' => [
                    ['Street Light Not Working', '\u0938\u094d\u091f\u094d\u0930\u0940\u091f \u0932\u093e\u0907\u091f \u0916\u0930\u093e\u092c', 'medium'],
                    ['Frequent Power Cuts', '\u092c\u093e\u0930-\u092c\u093e\u0930 \u092c\u093f\u091c\u0932\u0940 \u0915\u091f\u094c\u0924\u0940', 'high'],
                    ['Transformer Failure', '\u091f\u094d\u0930\u093e\u0902\u0938\u092b\u093e\u0930\u094d\u092e\u0930 \u0916\u0930\u093e\u092c', 'urgent'],
                    ['Damaged / Leaning Pole', '\u0915\u094d\u0937\u0924\u093f\u0917\u094d\u0930\u0938\u094d\u0924 \u0916\u0902\u092d\u093e', 'urgent'],
                    ['Loose / Sparking Wire', '\u0922\u0940\u0932\u0940 / \u0938\u094d\u092a\u093e\u0930\u094d\u0915\u093f\u0902\u0917 \u0924\u093e\u0930', 'urgent'],
                    ['Voltage Fluctuation', '\u0935\u094b\u0932\u094d\u091f\u0947\u091c \u0909\u0924\u093e\u0930-\u091a\u0922\u093c\u093e\u0935', 'medium'],
                ],
            ],
            'PR' => [
                'assets' => [
                    ['Drainage / Naali', '\u0928\u093e\u0932\u0940'],
                    ['Panchayat Bhawan', '\u092a\u0902\u091a\u093e\u092f\u0924 \u092d\u0935\u0928'],
                    ['Community Center / Chaupal', '\u0938\u093e\u092e\u0941\u0926\u093e\u092f\u093f\u0915 \u0915\u0947\u0902\u0926\u094d\u0930 / \u091a\u094c\u092a\u093e\u0932'],
                    ['Sports Ground', '\u0916\u0947\u0932 \u0915\u093e \u092e\u0948\u0926\u093e\u0928'],
                ],
                'categories' => [
                    ['Drainage Blocked / Overflow', '\u0928\u093e\u0932\u0940 \u091c\u093e\u092e / \u0913\u0935\u0930\u092b\u094d\u0932\u094b', 'high'],
                    ['Drainage Not Constructed', '\u0928\u093e\u0932\u0940 \u0915\u093e \u0928\u093f\u0930\u094d\u092e\u093e\u0923 \u0928\u0939\u0940\u0902', 'low'],
                    ['Building Maintenance', '\u092d\u0935\u0928 \u092e\u0930\u092e\u094d\u092e\u0924', 'low'],
                    ['Encroachment', '\u0905\u0924\u093f\u0915\u094d\u0930\u092e\u0923', 'medium'],
                    ['Ground Maintenance', '\u092e\u0948\u0926\u093e\u0928 \u0915\u0940 \u0926\u0947\u0916\u092d\u093e\u0932', 'low'],
                ],
            ],
            'SBM' => [
                'assets' => [
                    ['Public Toilet', '\u0938\u093e\u0930\u094d\u0935\u091c\u0928\u093f\u0915 \u0936\u094c\u091a\u093e\u0932\u092f'],
                    ['Garbage Collection', '\u0915\u091a\u0930\u093e \u0938\u0902\u0917\u094d\u0930\u0939\u0923'],
                    ['Sewage System', '\u0938\u0940\u0935\u0947\u091c \u0938\u093f\u0938\u094d\u091f\u092e'],
                ],
                'categories' => [
                    ['Toilet Not Functional', '\u0936\u094c\u091a\u093e\u0932\u092f \u0915\u093e\u092e \u0928\u0939\u0940\u0902 \u0915\u0930 \u0930\u0939\u093e', 'high'],
                    ['Toilet Uncleaned', '\u0936\u094c\u091a\u093e\u0932\u092f \u0917\u0902\u0926\u093e', 'medium'],
                    ['Garbage Not Collected', '\u0915\u091a\u0930\u093e \u0928\u0939\u0940\u0902 \u0909\u0920\u093e\u092f\u093e \u0917\u092f\u093e', 'medium'],
                    ['No Dustbins in Area', '\u0915\u094d\u0937\u0947\u0924\u094d\u0930 \u092e\u0947\u0902 \u0921\u0938\u094d\u091f\u092c\u093f\u0928 \u0928\u0939\u0940\u0902', 'low'],
                    ['Sewage Overflow', '\u0938\u0940\u0935\u0947\u091c \u0913\u0935\u0930\u092b\u094d\u0932\u094b', 'urgent'],
                ],
            ],
            'HEALTH' => [
                'assets' => [
                    ['PHC / Sub Health Center', '\u092a\u094d\u0930\u093e\u0925\u092e\u093f\u0915 \u0938\u094d\u0935\u093e\u0938\u094d\u0925\u094d\u092f \u0915\u0947\u0902\u0926\u094d\u0930'],
                    ['Ambulance Service', '\u090f\u092e\u094d\u092c\u0941\u0932\u0947\u0902\u0938 \u0938\u0947\u0935\u093e'],
                ],
                'categories' => [
                    ['Doctor Not Available', '\u0921\u0949\u0915\u094d\u091f\u0930 \u0909\u092a\u0932\u092c\u094d\u0927 \u0928\u0939\u0940\u0902', 'high'],
                    ['Medicine Shortage', '\u0926\u0935\u093e\u0907\u092f\u094b\u0902 \u0915\u0940 \u0915\u092e\u0940', 'high'],
                    ['Facility Closed / Irregular', '\u0915\u0947\u0902\u0926\u094d\u0930 \u092c\u0902\u0926 / \u0905\u0928\u093f\u092f\u092e\u093f\u0924', 'medium'],
                    ['Ambulance Not Available', '\u090f\u092e\u094d\u092c\u0941\u0932\u0947\u0902\u0938 \u0909\u092a\u0932\u092c\u094d\u0927 \u0928\u0939\u0940\u0902', 'urgent'],
                ],
            ],
            'EDU' => [
                'assets' => [
                    ['Government School', '\u0938\u0930\u0915\u093e\u0930\u0940 \u0938\u094d\u0915\u0942\u0932'],
                    ['Anganwadi Center', '\u0906\u0902\u0917\u0928\u0935\u093e\u0921\u093c\u0940 \u0915\u0947\u0902\u0926\u094d\u0930'],
                ],
                'categories' => [
                    ['Teacher Absent / Shortage', '\u0936\u093f\u0915\u094d\u0937\u0915 \u0905\u0928\u0941\u092a\u0938\u094d\u0925\u093f\u0924 / \u0915\u092e\u0940', 'medium'],
                    ['Building Damage', '\u092d\u0935\u0928 \u0915\u094d\u0937\u0924\u093f\u0917\u094d\u0930\u0938\u094d\u0924', 'medium'],
                    ['No Mid-day Meal', '\u092e\u0927\u094d\u092f\u093e\u0939\u094d\u0928 \u092d\u094b\u091c\u0928 \u0928\u0939\u0940\u0902', 'high'],
                    ['Infrastructure Issue', '\u092c\u0941\u0928\u093f\u092f\u093e\u0926\u0940 \u0922\u093e\u0902\u091a\u0947 \u0915\u0940 \u0938\u092e\u0938\u094d\u092f\u093e', 'low'],
                ],
            ],
            'IRR' => [
                'assets' => [
                    ['Canal / Nehar', '\u0928\u0939\u0930'],
                    ['Tubewell', '\u091f\u094d\u092f\u0942\u092c\u0935\u0947\u0932'],
                ],
                'categories' => [
                    ['Canal Blockage', '\u0928\u0939\u0930 \u0905\u0935\u0930\u0941\u0926\u094d\u0927', 'high'],
                    ['No Water Release', '\u092a\u093e\u0928\u0940 \u0928\u0939\u0940\u0902 \u091b\u094b\u0921\u093c\u093e \u0917\u092f\u093e', 'high'],
                    ['Canal Breach / Damage', '\u0928\u0939\u0930 \u091f\u0942\u091f\u0928\u093e / \u0915\u094d\u0937\u0924\u093f', 'urgent'],
                    ['Water Theft / Dispute', '\u092a\u093e\u0928\u0940 \u091a\u094b\u0930\u0940 / \u0935\u093f\u0935\u093e\u0926', 'medium'],
                ],
            ],
            'AGRI' => [
                'assets' => [
                    ['Mandi / Market', '\u092e\u0902\u0921\u0940'],
                    ['Seed Distribution Center', '\u092c\u0940\u091c \u0935\u093f\u0924\u0930\u0923 \u0915\u0947\u0902\u0926\u094d\u0930'],
                ],
                'categories' => [
                    ['Fertilizer Shortage', '\u0916\u093e\u0926 \u0915\u0940 \u0915\u092e\u0940', 'high'],
                    ['MSP Payment Issue', '\u090f\u092e\u090f\u0938\u092a\u0940 \u092d\u0941\u0917\u0924\u093e\u0928 \u0938\u092e\u0938\u094d\u092f\u093e', 'high'],
                    ['Poor Seed Quality', '\u092c\u0940\u091c \u0915\u0940 \u0917\u0941\u0923\u0935\u0924\u094d\u0924\u093e \u0916\u0930\u093e\u092c', 'medium'],
                ],
            ],
            'AH' => [
                'assets' => [
                    ['Veterinary Hospital', '\u092a\u0936\u0941 \u091a\u093f\u0915\u093f\u0924\u094d\u0938\u093e\u0932\u092f'],
                ],
                'categories' => [
                    ['Vet Not Available', '\u092a\u0936\u0941 \u091a\u093f\u0915\u093f\u0924\u094d\u0938\u0915 \u0909\u092a\u0932\u092c\u094d\u0927 \u0928\u0939\u0940\u0902', 'high'],
                    ['Medicine Shortage', '\u0926\u0935\u093e\u0907\u092f\u094b\u0902 \u0915\u0940 \u0915\u092e\u0940', 'medium'],
                ],
            ],
            'WCD' => [
                'assets' => [
                    ['Anganwadi Center', '\u0906\u0902\u0917\u0928\u0935\u093e\u0921\u093c\u0940 \u0915\u0947\u0902\u0926\u094d\u0930'],
                ],
                'categories' => [
                    ['Nutrition Supply Shortage', '\u092a\u094b\u0937\u0923 \u0906\u092a\u0942\u0930\u094d\u0924\u093f \u0915\u0940 \u0915\u092e\u0940', 'high'],
                    ['Center Closed / Irregular', '\u0915\u0947\u0902\u0926\u094d\u0930 \u092c\u0902\u0926 / \u0905\u0928\u093f\u092f\u092e\u093f\u0924', 'medium'],
                    ['Worker Absent', '\u0915\u093e\u0930\u094d\u092f\u0915\u0930\u094d\u0924\u093e \u0905\u0928\u0941\u092a\u0938\u094d\u0925\u093f\u0924', 'medium'],
                ],
            ],
        ];
    }
}
