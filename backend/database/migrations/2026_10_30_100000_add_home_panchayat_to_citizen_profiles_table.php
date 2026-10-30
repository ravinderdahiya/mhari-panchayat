<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('citizen_profiles', function (Blueprint $table) {
            // The panchayat a citizen may file complaints in; set once, from their first location.
            $table->unsignedBigInteger('home_panchayat_id')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('citizen_profiles', function (Blueprint $table) {
            $table->dropColumn('home_panchayat_id');
        });
    }
};
