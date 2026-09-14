<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    // Pivot for multi-panchayat coverage - real Gram Sachiv data has one
    // official holding "additional charge" of several Gram Panchayats under
    // a single mobile number, which the single users.panchayat_id column
    // can't represent without one charge silently overwriting another.
    public function up(): void
    {
        Schema::create('user_panchayats', function ($table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('panchayat_id')->constrained('panchayats')->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['user_id', 'panchayat_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('user_panchayats');
    }
};
