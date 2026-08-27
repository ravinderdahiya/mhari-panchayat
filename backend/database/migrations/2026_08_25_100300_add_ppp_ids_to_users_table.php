<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// CPLO source data carries each official's Parivar Pehchan Patra (PPP)
// identifiers - Member_id (the person) and family_id (their household).
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('member_id')->nullable()->after('employee_id');
            $table->string('family_id')->nullable()->after('member_id');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['member_id', 'family_id']);
        });
    }
};
