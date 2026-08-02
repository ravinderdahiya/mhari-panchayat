<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('complaints', function (Blueprint $table) {
            $table->foreignId('district_id')->nullable()->after('priority_id')->constrained('districts')->nullOnDelete();
            $table->foreignId('tehsil_id')->nullable()->after('district_id')->constrained('tehsils')->nullOnDelete();
            $table->foreignId('village_id')->nullable()->after('tehsil_id')->constrained('villages')->nullOnDelete();
            $table->foreignId('panchayat_id')->nullable()->after('village_id')->constrained('panchayats')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('complaints', function (Blueprint $table) {
            $table->dropConstrainedForeignId('panchayat_id');
            $table->dropConstrainedForeignId('village_id');
            $table->dropConstrainedForeignId('tehsil_id');
            $table->dropConstrainedForeignId('district_id');
        });
    }
};
