<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// One row per stage action, so a later stage's action (e.g. DDPO approving)
// never overwrites an earlier stage's reviewer identity - asset_surveys'
// own reviewed_by_id/reviewed_at/rejection_reason columns still track only
// the most recent action for quick list-view display.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('asset_survey_reviews', function (Blueprint $table) {
            $table->id();
            $table->foreignId('survey_id')->constrained('asset_surveys')->cascadeOnDelete();
            $table->foreignId('actor_id')->constrained('users');
            $table->string('actor_role', 30);
            $table->string('action', 20);
            $table->text('remarks')->nullable();
            $table->timestamps();

            $table->index('survey_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('asset_survey_reviews');
    }
};
