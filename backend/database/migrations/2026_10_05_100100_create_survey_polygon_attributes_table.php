<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        // Attribute data for a polygon, kept apart from the geometry table (1:1).
        // Keep the fixed columns in sync with config/survey.php `attribute_fields`.
        Schema::create('survey_polygon_attributes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('polygon_id')->unique()->constrained('survey_polygons')->cascadeOnDelete();
            $table->string('owner_name')->nullable();
            $table->string('father_name')->nullable();
            $table->string('mobile', 20)->nullable();
            $table->string('village')->nullable();
            $table->string('tehsil')->nullable();
            $table->string('district')->nullable();
            $table->string('khasra_no', 100)->nullable();
            $table->string('murabba_no', 100)->nullable();
            $table->string('crop')->nullable();
            $table->text('remarks')->nullable();
            $table->jsonb('extra')->nullable();
            $table->timestamps();

            $table->index('village');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('survey_polygon_attributes');
    }
};
