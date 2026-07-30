<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Phone/email verification now happens before the user record even exists
// (short-lived Cache entries keyed by mobile/email), so these per-user token
// columns are no longer written or read anywhere. email_verified_at and
// phone_verified_at stay - they're set to now() once verified.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'email_verification_token', 'email_verification_expires_at',
                'phone_otp', 'phone_otp_expires_at',
            ]);
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('email_verification_token')->nullable();
            $table->timestamp('email_verification_expires_at')->nullable();
            $table->string('phone_otp', 6)->nullable();
            $table->timestamp('phone_otp_expires_at')->nullable();
        });
    }
};
