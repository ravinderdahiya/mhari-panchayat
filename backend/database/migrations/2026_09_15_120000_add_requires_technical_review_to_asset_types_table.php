<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Drives the "XEN-PR (if technical)" branch of the verification escalation
// chain: after DDPO approves, a survey only routes through the XEN-PR
// (Executive Engineer) technical-review stage when its asset type is
// flagged as requiring one. Defaults true - every current asset type is
// physical Panchayati Raj infrastructure (hand pumps, drainage, buildings),
// so today every survey goes through XEN-PR until an admin marks specific
// non-technical types (e.g. a records/registry-only asset) otherwise.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('asset_types', function (Blueprint $table) {
            $table->boolean('requires_technical_review')->default(true)->after('is_active');
        });
    }

    public function down(): void
    {
        Schema::table('asset_types', function (Blueprint $table) {
            $table->dropColumn('requires_technical_review');
        });
    }
};
