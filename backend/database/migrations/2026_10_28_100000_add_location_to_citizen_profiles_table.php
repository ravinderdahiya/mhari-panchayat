<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('citizen_profiles', function (Blueprint $table) {
            $table->double('latitude')->nullable();
            $table->double('longitude')->nullable();
            $table->string('state')->nullable();
            $table->string('district')->nullable();
            $table->string('tehsil')->nullable();
            $table->string('block')->nullable();
            $table->string('panchayat')->nullable();
            $table->string('village')->nullable();
            $table->text('address')->nullable();
            $table->timestamp('location_updated_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('citizen_profiles', function (Blueprint $table) {
            $table->dropColumn(['latitude', 'longitude', 'state', 'district', 'tehsil', 'block', 'panchayat', 'village', 'address', 'location_updated_at']);
        });
    }
};
