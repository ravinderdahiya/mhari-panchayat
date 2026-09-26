<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Read-only directory of elected Panchayati Raj representatives who
        // are not portal users (Zila Parishad members, Panchayat Samiti
        // members, Panches) - source: "ER-Data.xlsx". Sarpanches are the one
        // tier in that workbook that already has a login role in this app
        // (see App\Enums\Role::Sarpanch), so they're imported as `users`
        // instead (see officials:import-sarpanches) and don't appear here.
        Schema::create('elected_representatives', function (Blueprint $table) {
            $table->id();
            $table->string('tier'); // zp | ps | panch
            $table->foreignId('district_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('block_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('panchayat_id')->nullable()->constrained()->nullOnDelete();
            $table->string('ward_no')->nullable();
            $table->string('name');
            $table->string('father_name')->nullable();
            $table->string('mobile')->nullable();
            $table->string('gender')->nullable();
            // Row number from its source sheet - stable natural key per tier,
            // used to make repeat imports of the same workbook idempotent.
            $table->unsignedInteger('source_sr_no');
            $table->timestamps();

            $table->unique(['tier', 'source_sr_no']);
            $table->index(['tier', 'district_id']);
            $table->index(['tier', 'block_id']);
            $table->index(['tier', 'panchayat_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('elected_representatives');
    }
};
