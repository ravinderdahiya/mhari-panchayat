<?php

namespace Database\Seeders;

use App\Models\AssetType;
use App\Models\Department;
use Illuminate\Database\Seeder;

/**
 * Seeds infrastructure assets + owning departments from the panchayat PDF
 * (S.No. Infrastructure Asset / Primary Department).
 */
class InfrastructureAssetSeeder extends Seeder
{
    public function run(): void
    {
        // [asset name, icon_key, department name(s)]
        $rows = [
            ['Govt. Primary School', 'school', ['School Education Department']],
            ['Govt. High School', 'school', ['School Education Department']],
            ['Govt. Senior Secondary School', 'school', ['School Education Department']],
            ['Veterinary Hospital', 'pets', ['Animal Husbandry & Dairying Department']],
            ['Anganwadi Center', 'child_care', ['Women & Child Development Department']],
            ['Community Health Center (CHC)', 'local_hospital', ['Health & Family Welfare Department']],
            ['Public Health Center (PHC)', 'medical_services', ['Health & Family Welfare Department']],
            ['Sports Stadium', 'stadium', ['Sports Department']],
            ['Gram Sachivalaya', 'gavel', ['Development & Panchayats Department']],
            ['Women Chaupal', 'woman', ['Development & Panchayats Department', 'Women & Child Development Department']],
            ['SC Chaupal', 'diversity_3', ['Development & Panchayats Department']],
            ['BC Chaupal', 'diversity_3', ['Development & Panchayats Department']],
            ['General Chaupal', 'forum', ['Development & Panchayats Department']],
            ['Shamshan Ghat', 'local_fire_department', ['Gram Panchayat', 'Development & Panchayats Department']],
            ['Kabristan', 'church', ['Gram Panchayat', 'Development & Panchayats Department']],
            ['Community Center', 'groups', ['Development & Panchayats Department', 'Urban Local Bodies']],
            ['Old Age Home', 'elderly', ['Social Justice & Empowerment Department']],
            ['Panchayat Ghar', 'account_balance', ['Development & Panchayats Department']],
            ['Tubewell', 'water_drop', ['Public Health Engineering Department', 'Agriculture Department']],
            ['Post Office', 'local_post_office', ['Department of Posts']],
            ['Patwar Bhawan', 'home_work', ['Revenue & Disaster Management Department']],
            ['Religious Place', 'temple_hindu', ['Gram Panchayat', 'Revenue & Disaster Management Department']],
            ['Street', 'alt_route', ['Public Works Department', 'Gram Panchayat', 'Rural Development Department']],
            ['Open Space', 'landscape', ['Gram Panchayat', 'Development & Panchayats Department']],
            ['Gym', 'fitness_center', ['Sports Department', 'Gram Panchayat']],
            ['Library', 'local_library', ['Higher Education Department', 'Development & Panchayats Department']],
            ['Mahila Sanskriti Kendra', 'spa', ['Women & Child Development Department']],
            ['Rajiv Gandhi Seva Kendra', 'handshake', ['Rural Development Department']],
            ['Bus Queue Shelter', 'directions_bus', ['Transport Department']],
            ['Solar Light Pole', 'wb_sunny', ['Haryana Renewable Energy Development Agency', 'Gram Panchayat']],
            ['Zila Parishad Building', 'domain', ['Rural Development & Panchayats Department']],
            ['Block Office Building', 'business', ['Rural Development & Panchayats Department']],
            ['Park-cum-Vyayamshala', 'park', ['Development & Panchayats Department', 'Sports Department']],
        ];

        $deptCodes = [
            'School Education Department' => 'SED',
            'Animal Husbandry & Dairying Department' => 'AHD',
            'Women & Child Development Department' => 'WCD',
            'Health & Family Welfare Department' => 'HFW',
            'Sports Department' => 'SPORTS',
            'Development & Panchayats Department' => 'DPD',
            'Gram Panchayat' => 'GP',
            'Urban Local Bodies' => 'ULB',
            'Social Justice & Empowerment Department' => 'SJE',
            'Public Health Engineering Department' => 'PHED',
            'Agriculture Department' => 'AGRI',
            'Department of Posts' => 'POSTS',
            'Revenue & Disaster Management Department' => 'RDM',
            'Public Works Department' => 'PWD',
            'Rural Development Department' => 'RDD',
            'Higher Education Department' => 'HED',
            'Transport Department' => 'TRANSPORT',
            'Haryana Renewable Energy Development Agency' => 'HAREDA',
            'Rural Development & Panchayats Department' => 'RDPD',
        ];

        $departmentIds = [];
        foreach ($deptCodes as $name => $code) {
            $department = Department::firstOrCreate(
                ['name' => $name],
                ['code' => $code],
            );
            if (! $department->code) {
                $department->update(['code' => $code]);
            }
            $departmentIds[$name] = $department->id;
        }

        foreach ($rows as $index => [$name, $iconKey, $deptNames]) {
            $assetType = AssetType::updateOrCreate(
                ['name' => $name],
                [
                    'icon_key' => $iconKey,
                    'sort_order' => $index + 1,
                    'is_active' => true,
                ],
            );

            $ids = [];
            foreach ($deptNames as $deptName) {
                if (isset($departmentIds[$deptName])) {
                    $ids[] = $departmentIds[$deptName];
                }
            }
            $assetType->departments()->sync($ids);
        }
    }
}
