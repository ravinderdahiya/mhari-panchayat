<?php

use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Pivot for multi-department assignment to surveyors (and other staff).
        if (! Schema::hasTable('department_user')) {
            Schema::create('department_user', function ($table) {
                $table->id();
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
                $table->foreignId('department_id')->constrained('departments')->cascadeOnDelete();
                $table->timestamps();
                $table->unique(['user_id', 'department_id']);
            });
        }

        // Seed pivot from existing single department_id where present.
        if (Schema::hasColumn('users', 'department_id')) {
            $rows = DB::table('users')
                ->whereNotNull('department_id')
                ->get(['id', 'department_id']);
            $now = now();
            foreach ($rows as $row) {
                DB::table('department_user')->insertOrIgnore([
                    'user_id' => $row->id,
                    'department_id' => $row->department_id,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            }
        }

        // Auto emp codes for surveyors missing one: SUR-{DIST|GEN}-{id}
        $engineers = User::with('district')->where('role', 'engineer')->whereNull('employee_id')->get();
        foreach ($engineers as $user) {
            $distCode = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string) ($user->district?->code ?: 'GEN')) ?: 'GEN');
            $user->forceFill([
                'employee_id' => sprintf('SUR-%s-%04d', $distCode, $user->id),
            ])->save();
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('department_user');
    }
};
