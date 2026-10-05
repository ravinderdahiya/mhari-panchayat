<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() !== 'pgsql' || ! Schema::hasTable('survey_polygons')) {
            return;
        }

        // "What is this route for?" - the description typed in the app's Start route dialog.
        Schema::table('survey_polygons', function (Blueprint $table) {
            $table->string('description', 500)->nullable()->after('uuid');
        });
    }

    public function down(): void
    {
        if (Schema::hasColumn('survey_polygons', 'description')) {
            Schema::table('survey_polygons', function (Blueprint $table) {
                $table->dropColumn('description');
            });
        }
    }
};
