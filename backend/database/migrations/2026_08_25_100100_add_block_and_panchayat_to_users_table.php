<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Lets a staff user's jurisdiction be pinned to a single block (BDPO) or
// panchayat (CPLO/Gram Sachiv) - the granularity the existing district_id
// column can't express, and the granularity real BDPO/CPLO data comes at.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->foreignId('block_id')->nullable()->after('district_id')->constrained()->nullOnDelete();
            $table->foreignId('panchayat_id')->nullable()->after('block_id')->constrained()->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropConstrainedForeignId('panchayat_id');
            $table->dropConstrainedForeignId('block_id');
        });
    }
};
