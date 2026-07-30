<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// The registration workflow now collects the registrant's password upfront
// (at registration time) instead of via a post-approval "set password" step,
// so these columns are no longer written or read anywhere.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['set_password_token', 'set_password_token_expires_at']);
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('set_password_token')->nullable();
            $table->timestamp('set_password_token_expires_at')->nullable();
        });
    }
};
