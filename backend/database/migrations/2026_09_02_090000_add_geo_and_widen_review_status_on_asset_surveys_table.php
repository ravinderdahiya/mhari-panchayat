<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// BDPO/DDPO stages need block/district scoping the same way gram_sachiv
// already scopes on panchayat_id - denormalized here (like panchayat_id was)
// rather than resolved via join on every request.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('asset_surveys', function (Blueprint $table) {
            $table->foreignId('block_id')->nullable()->after('panchayat_id')->constrained('blocks')->nullOnDelete();
            $table->foreignId('district_id')->nullable()->after('block_id')->constrained('districts')->nullOnDelete();
            $table->string('review_status', 30)->default('pending')->change();
        });

        DB::statement(<<<'SQL'
            UPDATE asset_surveys
            SET block_id = panchayats.block_id,
                district_id = blocks.district_id
            FROM panchayats
            JOIN blocks ON blocks.id = panchayats.block_id
            WHERE asset_surveys.panchayat_id = panchayats.id
        SQL);
    }

    public function down(): void
    {
        Schema::table('asset_surveys', function (Blueprint $table) {
            $table->dropConstrainedForeignId('district_id');
            $table->dropConstrainedForeignId('block_id');
            $table->string('review_status', 20)->default('pending')->change();
        });
    }
};
