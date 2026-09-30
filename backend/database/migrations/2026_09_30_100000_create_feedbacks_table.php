<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('feedbacks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            // Snapshot of the submitter's role at submission time - stays
            // accurate for reporting even if the user's role changes later.
            $table->string('user_role', 30);
            $table->string('category', 20);
            $table->unsignedTinyInteger('rating')->nullable();
            $table->text('message');
            $table->string('photo_path')->nullable();
            $table->timestamps();

            $table->index('user_id');
            $table->index('category');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('feedbacks');
    }
};
