<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('asset_surveys', function (Blueprint $table) {
            $table->id();
            $table->string('asset_code')->nullable()->unique();
            $table->foreignId('surveyor_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('department_id')->constrained('departments')->restrictOnDelete();
            $table->foreignId('asset_type_id')->constrained('asset_types')->restrictOnDelete();
            $table->string('asset_name', 200);
            $table->string('district', 150);
            $table->string('panchayat', 150);
            $table->string('village', 150);
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->string('condition', 20);
            $table->text('description')->nullable();
            $table->dateTime('survey_date');
            $table->json('photo_paths');
            $table->timestamps();

            $table->index(['surveyor_id', 'created_at']);
            $table->index(['department_id', 'asset_type_id']);
            $table->index(['district', 'village']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('asset_surveys');
    }
};
