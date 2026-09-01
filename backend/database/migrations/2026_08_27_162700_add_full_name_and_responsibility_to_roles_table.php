<?php

use App\Models\Role;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('roles', function (Blueprint $table) {
            $table->string('full_name')->nullable()->after('name');
            $table->text('main_responsibility')->nullable()->after('full_name');
        });

        foreach (Role::CATALOG as $name => $details) {
            DB::table('roles')->where('name', $name)->update($details);
        }
    }

    public function down(): void
    {
        Schema::table('roles', function (Blueprint $table) {
            $table->dropColumn(['full_name', 'main_responsibility']);
        });
    }
};
