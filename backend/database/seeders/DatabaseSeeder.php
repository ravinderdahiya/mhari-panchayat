<?php

namespace Database\Seeders;

use App\Models\Block;
use App\Models\ComplaintCategory;
use App\Models\ComplaintPriority;
use App\Models\Department;
use App\Models\District;
use App\Models\Panchayat;
use App\Models\State;
use App\Models\Tehsil;
use App\Models\User;
use App\Models\Village;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    public function run(): void
    {
        $this->call(PermissionSeeder::class);

        User::create([
            'username' => 'testadmin',
            'password' => 'Admin@123',
            'name' => 'Test Admin',
            'email' => 'test@example.com',
            'role' => 'super_admin',
        ]);

        $state = State::create(['name' => 'Haryana', 'code' => 'HR']);
        $district = District::create(['name' => 'Sonipat', 'code' => 'SNP', 'short_code' => 'SNP', 'state_id' => $state->id]);
        $tehsil = Tehsil::create(['name' => 'Gohana', 'code' => 'GHN-T', 'district_id' => $district->id]);
        $block = Block::create(['name' => 'Gohana', 'code' => 'GHN', 'district_id' => $district->id]);
        $panchayat = Panchayat::create(['name' => 'Sisana Gram Panchayat', 'code' => 'SGP', 'block_id' => $block->id]);
        Village::create(['name' => 'Sisana', 'code' => 'SSN', 'panchayat_id' => $panchayat->id, 'tehsil_id' => $tehsil->id]);

        foreach ([
            ['name' => 'Public Works Department', 'code' => 'PWD'],
            ['name' => 'Health Department', 'code' => 'HLTH'],
            ['name' => 'Education Department', 'code' => 'EDU'],
        ] as $dept) {
            Department::create($dept);
        }

        foreach (['Low' => 1, 'Medium' => 2, 'High' => 3, 'Critical' => 4] as $name => $level) {
            ComplaintPriority::create(['name' => $name, 'level' => $level]);
        }

        foreach (['Pond', 'Road', 'Sanitation', 'Water_Supply', 'Building', 'Other'] as $name) {
            ComplaintCategory::create(['name' => $name]);
        }

        $this->call(InfrastructureAssetSeeder::class);
        $this->call(ComplaintMasterSeeder::class);
    }
}
