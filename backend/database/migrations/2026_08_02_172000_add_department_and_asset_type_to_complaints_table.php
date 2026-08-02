<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('complaints', function (Blueprint $table) {
            $table->foreignId('department_id')->nullable()->after('priority_id')->constrained('departments')->nullOnDelete();
            $table->foreignId('asset_type_id')->nullable()->after('department_id')->constrained('asset_types')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('complaints', function (Blueprint $table) {
            $table->dropConstrainedForeignId('asset_type_id');
            $table->dropConstrainedForeignId('department_id');
        });
    }
};
