<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('complaints', function (Blueprint $table) {
            $table->string('location_state')->nullable()->after('panchayat');
            $table->string('location_district')->nullable()->after('location_state');
            $table->string('location_tehsil')->nullable()->after('location_district');
            $table->string('location_block')->nullable()->after('location_tehsil');
        });
    }

    public function down(): void
    {
        Schema::table('complaints', function (Blueprint $table) {
            $table->dropColumn([
                'location_state',
                'location_district',
                'location_tehsil',
                'location_block',
            ]);
        });
    }
};
