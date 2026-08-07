<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('complaints', function (Blueprint $table) {
            $table->json('issue_photo_urls')->nullable()->after('before_photo_url');
        });

        // Backfill existing single before photos into the new multi-photo column.
        DB::table('complaints')
            ->whereNotNull('before_photo_url')
            ->where('before_photo_url', '!=', '')
            ->orderBy('id')
            ->chunkById(100, function ($rows) {
                foreach ($rows as $row) {
                    DB::table('complaints')->where('id', $row->id)->update([
                        'issue_photo_urls' => json_encode([$row->before_photo_url]),
                    ]);
                }
            });
    }

    public function down(): void
    {
        Schema::table('complaints', function (Blueprint $table) {
            $table->dropColumn('issue_photo_urls');
        });
    }
};
