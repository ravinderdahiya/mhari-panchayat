<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('village_assets', function (Blueprint $table) {
            $table->id();
            $table->foreignId('village_id')->constrained('villages')->cascadeOnDelete();
            $table->string('category');
            $table->string('subtype');
            $table->string('asset_name');
            $table->string('geometry_type'); // Point | Line | Polygon
            $table->double('latitude')->nullable();
            $table->double('longitude')->nullable();
            $table->json('path')->nullable(); // [[lat,long], ...] for Line/Polygon
            $table->string('status')->default('Working'); // Working | Not Working | Under Construction
            $table->string('condition')->default('Good'); // Good | Fair | Poor
            $table->integer('ward_no')->nullable();
            $table->date('installed_date')->nullable();
            $table->date('last_inspected')->nullable();
            $table->text('remarks')->nullable();
            $table->string('photo_url')->nullable();
            $table->foreignId('created_by')->constrained('users')->cascadeOnDelete();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('village_assets');
    }
};
