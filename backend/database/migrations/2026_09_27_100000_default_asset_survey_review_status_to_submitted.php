<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// AssetSurveyController::store() now always sets review_status explicitly
// (see the review-then-forward split added there), so this column default
// is no longer actually relied on for new rows - only kept in sync so a
// future direct insert doesn't silently land on a stage-visible status
// ('pending') before the surveyor has reviewed and forwarded their own
// submission.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('asset_surveys', function (Blueprint $table) {
            $table->string('review_status', 30)->default('submitted')->change();
        });
    }

    public function down(): void
    {
        Schema::table('asset_surveys', function (Blueprint $table) {
            $table->string('review_status', 30)->default('pending')->change();
        });
    }
};
