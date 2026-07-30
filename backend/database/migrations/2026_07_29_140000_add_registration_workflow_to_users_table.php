<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->foreignId('district_id')->nullable()->constrained('districts')->nullOnDelete();
            $table->string('employee_id')->nullable();
            $table->string('mobile')->nullable();

            // pending_email -> pending_phone -> pending_review -> approved -> active
            // (or -> rejected, from pending_review). Pre-existing/admin-created users
            // default to 'active' so this workflow only applies to new self-registrations.
            $table->string('registration_status')->default('active');

            $table->timestamp('email_verified_at')->nullable();
            $table->string('email_verification_token')->nullable();
            $table->timestamp('email_verification_expires_at')->nullable();

            $table->timestamp('phone_verified_at')->nullable();
            $table->string('phone_otp', 6)->nullable();
            $table->timestamp('phone_otp_expires_at')->nullable();

            $table->string('rejection_reason')->nullable();
            $table->foreignId('reviewed_by_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();

            $table->string('set_password_token')->nullable();
            $table->timestamp('set_password_token_expires_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropConstrainedForeignId('district_id');
            $table->dropConstrainedForeignId('reviewed_by_id');
            $table->dropColumn([
                'employee_id', 'mobile', 'registration_status',
                'email_verified_at', 'email_verification_token', 'email_verification_expires_at',
                'phone_verified_at', 'phone_otp', 'phone_otp_expires_at',
                'rejection_reason', 'reviewed_at',
                'set_password_token', 'set_password_token_expires_at',
            ]);
        });
    }
};
