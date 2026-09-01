<?php

namespace Database\Seeders;

use App\Enums\Role as RoleEnum;
use App\Models\Role;
use Illuminate\Database\Seeder;

class RoleSeeder extends Seeder
{
    public function run(): void
    {
        foreach (RoleEnum::values() as $name) {
            Role::updateOrCreate(
                ['name' => $name],
                [
                    'is_active' => true,
                    ...(Role::CATALOG[$name] ?? []),
                ],
            );
        }
    }
}
