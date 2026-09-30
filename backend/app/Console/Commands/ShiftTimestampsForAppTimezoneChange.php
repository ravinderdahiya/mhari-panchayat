<?php

namespace App\Console\Commands;

use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

#[Signature('timezone:shift-existing-data {--dry-run : Preview affected row counts without writing changes} {--force : Skip the confirmation prompt}')]
#[Description('One-time fix for switching APP_TIMEZONE from UTC to Asia/Kolkata: shifts every existing naive timestamp column forward by 5h30m so it still resolves to the same real-world instant once read back under the new default timezone')]
class ShiftTimestampsForAppTimezoneChange extends Command
{
    private const IST_OFFSET_MINUTES = 330;

    /**
     * Every "timestamp without time zone" column in the schema (from information_schema),
     * excluding pure DATE columns (village_assets.installed_date/last_inspected — no time-of-day,
     * unaffected) and integer/unix-timestamp columns (sessions.last_activity, jobs/cache tables —
     * timezone-invariant on read).
     */
    private const COLUMNS_BY_TABLE = [
        'asset_survey_reviews' => ['created_at', 'updated_at'],
        'asset_surveys' => ['created_at', 'reviewed_at', 'survey_date', 'updated_at'],
        'asset_type_department' => ['created_at', 'updated_at'],
        'asset_types' => ['created_at', 'updated_at'],
        'blocks' => ['created_at', 'updated_at'],
        'citizen_profiles' => ['created_at', 'last_login_at', 'registered_at', 'updated_at'],
        'complaint_categories' => ['created_at', 'updated_at'],
        'complaint_priorities' => ['created_at', 'updated_at'],
        'complaint_sequences' => ['created_at', 'updated_at'],
        'complaint_timeline_events' => ['created_at'],
        'complaint_transfers' => ['created_at'],
        'complaints' => ['created_at', 'escalated_at', 'resolved_at', 'sla_due_at', 'updated_at', 'verified_at'],
        'department_user' => ['created_at', 'updated_at'],
        'departments' => ['created_at', 'updated_at'],
        'designations' => ['created_at', 'updated_at'],
        'districts' => ['created_at', 'updated_at'],
        'elected_representatives' => ['created_at', 'updated_at'],
        'failed_jobs' => ['failed_at'],
        'panchayats' => ['created_at', 'updated_at'],
        'password_reset_tokens' => ['created_at', 'expires_at'],
        'permissions' => ['created_at', 'updated_at'],
        'personal_access_tokens' => ['created_at', 'expires_at', 'last_used_at', 'updated_at'],
        'role_permissions' => ['created_at', 'updated_at'],
        'roles' => ['created_at', 'updated_at'],
        'states' => ['created_at', 'updated_at'],
        'tehsils' => ['created_at', 'updated_at'],
        'user_blocks' => ['created_at', 'updated_at'],
        'user_notifications' => ['created_at', 'updated_at'],
        'user_panchayats' => ['created_at', 'updated_at'],
        'user_villages' => ['created_at', 'updated_at'],
        'users' => [
            'created_at', 'email_verification_expires_at', 'email_verified_at',
            'phone_verified_at', 'reviewed_at', 'set_password_token_expires_at', 'updated_at',
        ],
        'village_assets' => ['created_at', 'updated_at'],
        'villages' => ['created_at', 'updated_at'],
    ];

    public function handle(): void
    {
        $this->info('Planned shift: +'.self::IST_OFFSET_MINUTES." minutes on every column below (NULLs left untouched).\n");

        $rows = [];
        foreach (self::COLUMNS_BY_TABLE as $table => $columns) {
            $count = DB::table($table)->count();
            $rows[] = [$table, implode(', ', $columns), $count];
        }
        $this->table(['Table', 'Columns', 'Row count'], $rows);

        if ($this->option('dry-run')) {
            $this->comment('Dry run only — no changes written.');

            return;
        }

        $totalTables = count(self::COLUMNS_BY_TABLE);
        if (! $this->option('force') && ! $this->confirm("Shift timestamps on all {$totalTables} table(s) listed above? This cannot be undone automatically.")) {
            $this->warn('Aborted. No changes made.');

            return;
        }

        DB::transaction(function () {
            foreach (self::COLUMNS_BY_TABLE as $table => $columns) {
                $update = [];
                foreach ($columns as $column) {
                    $update[$column] = DB::raw("\"{$column}\" + INTERVAL '".self::IST_OFFSET_MINUTES." minutes'");
                }

                $updated = DB::table($table)->update($update);
                $this->info("{$table}: {$updated} row(s) updated.");
            }
        });

        $this->info('Done.');
    }
}
