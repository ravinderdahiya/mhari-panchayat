<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// districts.code already holds the numeric census code used to build
// employee IDs (SUR-<code>-0001) - short_code is a separate 3-letter
// abbreviation (Sonipat -> SNP) used only for the human-facing complaint
// code (COMP-<short_code>-<MM_YYYY>-<seq>), so neither use steps on the other.
return new class extends Migration
{
    private const SHORT_CODES = [
        'Ambala' => 'AMB',
        'Bhiwani' => 'BHI',
        'Charkhi Dadri' => 'CKD',
        'Faridabad' => 'FBD',
        'Fatehabad' => 'FTH',
        'Gurugram' => 'GGN',
        'Hansi' => 'HNS',
        'Hisar' => 'HSR',
        'Jhajjar' => 'JHJ',
        'Jind' => 'JND',
        'Kaithal' => 'KTL',
        'Karnal' => 'KNL',
        'Kurukshetra' => 'KKT',
        'Mahendragarh' => 'MGH',
        'Nuh' => 'NUH',
        'Palwal' => 'PWL',
        'Panchkula' => 'PKL',
        'Panipat' => 'PNP',
        'Rewari' => 'RWR',
        'Rohtak' => 'ROH',
        'Sirsa' => 'SRS',
        'Sonipat' => 'SNP',
        'Yamunanagar' => 'YNR',
    ];

    public function up(): void
    {
        Schema::table('districts', function (Blueprint $table) {
            $table->string('short_code', 10)->nullable()->after('code');
        });

        foreach (self::SHORT_CODES as $name => $shortCode) {
            DB::table('districts')->where('name', $name)->update(['short_code' => $shortCode]);
        }
    }

    public function down(): void
    {
        Schema::table('districts', function (Blueprint $table) {
            $table->dropColumn('short_code');
        });
    }
};
