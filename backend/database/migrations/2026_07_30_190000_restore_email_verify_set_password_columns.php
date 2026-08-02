<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Restore post-signup email-verify + set-password columns so registration
// matches the basmati-survey-app lifecycle:
//   pending_email → (verify email) → email_verified → (set password) → pending_review
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'email_verification_token')) {
                $table->string('email_verification_token')->nullable()->after('email_verified_at');
            }
            if (! Schema::hasColumn('users', 'email_verification_expires_at')) {
                $table->timestamp('email_verification_expires_at')->nullable()->after('email_verification_token');
            }
            if (! Schema::hasColumn('users', 'set_password_token')) {
                $table->string('set_password_token')->nullable()->after('phone_verified_at');
            }
            if (! Schema::hasColumn('users', 'set_password_token_expires_at')) {
                $table->timestamp('set_password_token_expires_at')->nullable()->after('set_password_token');
            }
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $cols = [];
            foreach ([
                'email_verification_token',
                'email_verification_expires_at',
                'set_password_token',
                'set_password_token_expires_at',
            ] as $col) {
                if (Schema::hasColumn('users', $col)) {
                    $cols[] = $col;
                }
            }
            if ($cols !== []) {
                $table->dropColumn($cols);
            }
        });
    }
};
