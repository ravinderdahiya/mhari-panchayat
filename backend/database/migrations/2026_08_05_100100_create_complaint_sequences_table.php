<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Backs the COMP-{districtCode}-{MM_YYYY}-{seq} complaint code: one row per
// (district, year, month) holds the last issued sequence number. Generation
// locks this row (SELECT ... FOR UPDATE) so concurrent submissions in the
// same district/month never race onto the same number.
//
// district_id is a plain (unconstrained) column using 0 as the "no district"
// sentinel, not a nullable FK: Postgres treats each NULL as distinct for a
// unique index, which would let every district-less complaint in a given
// month grab its own (district_id=NULL, year, month) row instead of sharing
// one - defeating the lock this table exists for.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('complaint_sequences', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('district_id')->default(0);
            $table->unsignedSmallInteger('year');
            $table->unsignedTinyInteger('month');
            $table->unsignedInteger('last_number')->default(0);
            $table->timestamps();

            $table->unique(['district_id', 'year', 'month']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('complaint_sequences');
    }
};
