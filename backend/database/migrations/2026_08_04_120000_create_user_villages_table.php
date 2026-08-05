<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Pivot for multi-village assignment to surveyors (survey coverage area).
        Schema::create('user_villages', function ($table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('village_id')->constrained('villages')->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['user_id', 'village_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('user_villages');
    }
};
