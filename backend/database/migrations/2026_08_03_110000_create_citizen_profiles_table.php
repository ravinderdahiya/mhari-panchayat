<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('citizen_profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('full_name')->nullable();
            $table->string('mobile', 20)->index();
            $table->string('email')->nullable();
            $table->string('registration_source')->default('mobile_app');
            $table->timestamp('registered_at');
            $table->timestamp('last_login_at')->nullable();
            $table->timestamps();
        });

        $now = now();
        foreach (DB::table('users')->where('role', 'citizen')->get() as $user) {
            DB::table('citizen_profiles')->insert([
                'user_id' => $user->id,
                'full_name' => $user->name,
                'mobile' => $user->mobile ?: $user->username,
                'email' => $user->email,
                'registration_source' => 'existing_data',
                'registered_at' => $user->created_at ?: $now,
                'last_login_at' => $user->phone_verified_at,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('citizen_profiles');
    }
};
