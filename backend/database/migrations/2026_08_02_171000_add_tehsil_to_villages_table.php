<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('villages', function (Blueprint $table) {
            $table->foreignId('tehsil_id')->nullable()->after('panchayat_id')->constrained('tehsils')->nullOnDelete();
        });

        $path = database_path('data/haryana_geography.json');
        if (! is_file($path)) {
            return;
        }

        $data = json_decode((string) file_get_contents($path), true);
        $tehsilIdByCode = DB::table('tehsils')->pluck('id', 'code');
        foreach (array_chunk($data['villages'] ?? [], 500) as $rows) {
            foreach ($rows as $row) {
                $tehsilId = $tehsilIdByCode->get((string) ($row['tehsil_code'] ?? ''));
                if ($tehsilId) {
                    DB::table('villages')
                        ->where('code', (string) $row['code'])
                        ->update(['tehsil_id' => $tehsilId]);
                }
            }
        }
    }

    public function down(): void
    {
        Schema::table('villages', function (Blueprint $table) {
            $table->dropConstrainedForeignId('tehsil_id');
        });
    }
};
