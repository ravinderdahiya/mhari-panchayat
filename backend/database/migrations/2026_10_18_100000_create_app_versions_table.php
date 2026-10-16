<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('app_versions', function (Blueprint $table) {
            $table->id();
            $table->string('platform', 20)->unique();
            // Compared against the app's build number (pubspec `version: x.y.z+BUILD`).
            $table->unsignedInteger('latest_version_code');
            // Anything below this is forced to update.
            $table->unsignedInteger('min_version_code');
            $table->string('store_url');
            $table->string('message')->nullable();
            $table->timestamps();
        });

        // Start permissive (nothing is forced) so deploying this never locks
        // existing installs out; raise the numbers from the admin panel per release.
        DB::table('app_versions')->insert([
            'platform' => 'android',
            'latest_version_code' => 1,
            'min_version_code' => 1,
            'store_url' => 'https://play.google.com/store/apps/details?id=in.hsac.mharipanchayat',
            'message' => null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('app_versions');
    }
};
