<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    // Notifications about the asset-survey review workflow (a survey waiting for
    // your review, returned / rejected / approved) point at the survey the same way
    // complaint notifications point at a complaint.
    public function up(): void
    {
        Schema::table('user_notifications', function (Blueprint $table) {
            $table->foreignId('asset_survey_id')->nullable()->after('complaint_id')
                ->constrained('asset_surveys')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('user_notifications', function (Blueprint $table) {
            $table->dropConstrainedForeignId('asset_survey_id');
        });
    }
};
