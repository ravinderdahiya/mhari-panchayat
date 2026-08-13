<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('complaint_priorities', function (Blueprint $table) {
            $table->unsignedInteger('sla_hours')->nullable();
        });

        foreach (['Low' => 120, 'Medium' => 72, 'High' => 24, 'Critical' => 8] as $name => $hours) {
            DB::table('complaint_priorities')->where('name', $name)->update(['sla_hours' => $hours]);
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('complaint_priorities', function (Blueprint $table) {
            $table->dropColumn('sla_hours');
        });
    }
};
