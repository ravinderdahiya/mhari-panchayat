<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

// `role` was already a plain string column (no Postgres enum to widen), so
// this only needs to: (1) change the default for new registrations from the
// placeholder 'user' to 'citizen', matching the real 12-role list now used
// by the Complaints workflow, and (2) fix up the handful of pre-existing
// test rows that predate that list ('user' -> 'citizen', 'admin' -> 'super_admin').
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE users ALTER COLUMN role SET DEFAULT 'citizen'");
        DB::table('users')->where('role', 'user')->update(['role' => 'citizen']);
        DB::table('users')->where('role', 'admin')->update(['role' => 'super_admin']);
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE users ALTER COLUMN role SET DEFAULT 'user'");
    }
};
