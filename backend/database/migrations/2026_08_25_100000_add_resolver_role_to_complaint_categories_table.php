<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// The CEO-triage flowchart's routing logic, made data-driven: each leaf
// category already knows its department (Panchayati Raj vs everything else)
// and asset type, so it can also carry the role that should resolve it -
// secretary/block_admin/engineer for the Panchayati Raj tiers (Gram
// Panchayat/Samiti/technical wing), deputy_commissioner for every other
// department. See ComplaintMasterSeeder for the actual assignments.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('complaint_categories', function (Blueprint $table) {
            $table->string('resolver_role')->nullable()->after('department_id');
        });
    }

    public function down(): void
    {
        Schema::table('complaint_categories', function (Blueprint $table) {
            $table->dropColumn('resolver_role');
        });
    }
};
