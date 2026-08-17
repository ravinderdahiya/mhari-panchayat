<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('asset_surveys', function (Blueprint $table) {
            // Admin review workflow, distinct from the surveyor-reported physical
            // `condition` (GOOD/FAIR/POOR/DAMAGED) - defaults to pending so every
            // existing survey lands in "Pending review" rather than silently
            // appearing pre-approved once this ships.
            $table->string('review_status', 20)->default('pending')->after('condition');
            $table->foreignId('reviewed_by_id')->nullable()->after('review_status')->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable()->after('reviewed_by_id');
            $table->text('rejection_reason')->nullable()->after('reviewed_at');

            $table->index('review_status');
        });
    }

    public function down(): void
    {
        Schema::table('asset_surveys', function (Blueprint $table) {
            $table->dropConstrainedForeignId('reviewed_by_id');
            $table->dropColumn(['review_status', 'reviewed_at', 'rejection_reason']);
        });
    }
};
