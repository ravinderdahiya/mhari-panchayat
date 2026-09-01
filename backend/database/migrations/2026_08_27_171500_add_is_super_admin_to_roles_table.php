<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('roles', function (Blueprint $table) {
            $table->boolean('is_super_admin')->default(false);
        });

        // One-time backfill: the current highest-admin row. Runtime code
        // uses this flag, not the role slug.
        DB::table('roles')->where('is_super_admin', true)->update(['is_super_admin' => false]);
        $marked = DB::table('roles')->where('name', 'super_admin')->update(['is_super_admin' => true]);
        if ($marked === 0) {
            DB::table('roles')->orderBy('id')->limit(1)->update(['is_super_admin' => true]);
        }
    }

    public function down(): void
    {
        Schema::table('roles', function (Blueprint $table) {
            $table->dropColumn('is_super_admin');
        });
    }
};
