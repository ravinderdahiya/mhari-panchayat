<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('complaints', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('assigned_to_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignId('category_id')->constrained('complaint_categories');
            $table->foreignId('priority_id')->constrained('complaint_priorities');
            $table->string('village')->nullable();
            $table->string('panchayat')->nullable();
            $table->text('description')->nullable();
            $table->double('lat')->nullable();
            $table->double('long')->nullable();
            $table->string('before_photo_url')->nullable();
            $table->string('during_photo_url')->nullable();
            $table->string('after_photo_url')->nullable();
            $table->string('voice_note_url')->nullable();
            $table->string('status')->default('Pending');
            $table->integer('citizen_rating')->nullable();
            $table->string('citizen_feedback')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('complaints');
    }
};
