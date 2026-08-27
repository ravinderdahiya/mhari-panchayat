<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    // Pivot for multi-block coverage - real BDPO data has officials holding
    // "additional charge" of 2-4 blocks at once with a single mobile number,
    // which a single users.block_id column can't represent without one
    // charge silently overwriting another.
    public function up(): void
    {
        Schema::create('user_blocks', function ($table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('block_id')->constrained('blocks')->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['user_id', 'block_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('user_blocks');
    }
};
