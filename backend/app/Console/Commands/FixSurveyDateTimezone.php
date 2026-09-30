<?php

namespace App\Console\Commands;

use App\Models\AssetSurvey;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

#[Signature('surveys:fix-timezone {--dry-run : Preview affected rows without writing changes} {--force : Skip the confirmation prompt}')]
#[Description('One-time fix for asset surveys submitted before the mobile app sent surveyDate as UTC: shifts survey_date back by 5h30m (IST offset) so it reflects the true capture instant')]
class FixSurveyDateTimezone extends Command
{
    private const IST_OFFSET_MINUTES = 330;

    public function handle(): void
    {
        $affected = AssetSurvey::query()->whereNotNull('survey_date')->count();

        if ($affected === 0) {
            $this->info('No asset surveys with a survey_date found. Nothing to do.');

            return;
        }

        $this->info("{$affected} asset survey(s) will have survey_date shifted back by 5h30m.");

        $sample = AssetSurvey::query()
            ->whereNotNull('survey_date')
            ->orderByDesc('id')
            ->limit(5)
            ->get(['id', 'asset_code', 'survey_date']);

        $this->table(
            ['ID', 'Asset code', 'Current survey_date', 'Corrected survey_date'],
            $sample->map(fn (AssetSurvey $s) => [
                $s->id,
                $s->asset_code,
                $s->survey_date?->toDateTimeString(),
                $s->survey_date?->copy()->subMinutes(self::IST_OFFSET_MINUTES)->toDateTimeString(),
            ])
        );

        if ($this->option('dry-run')) {
            $this->comment('Dry run only — no changes written.');

            return;
        }

        if (! $this->option('force') && ! $this->confirm("Shift survey_date back by 5h30m for all {$affected} row(s)? This cannot be undone automatically.")) {
            $this->warn('Aborted. No changes made.');

            return;
        }

        $updated = DB::table('asset_surveys')
            ->whereNotNull('survey_date')
            ->update([
                'survey_date' => DB::raw("survey_date - INTERVAL '".self::IST_OFFSET_MINUTES." minutes'"),
            ]);

        $this->info("Done. Corrected survey_date on {$updated} row(s).");
    }
}
