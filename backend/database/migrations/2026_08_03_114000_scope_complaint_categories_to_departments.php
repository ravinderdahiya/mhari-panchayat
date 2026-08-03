<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('complaint_categories', function (Blueprint $table) {
            $table->foreignId('department_id')->nullable()->constrained('departments')->cascadeOnDelete();
            $table->index(['department_id', 'asset_type_id', 'name']);
        });
    }

    public function down(): void
    {
        Schema::table('complaint_categories', function (Blueprint $table) {
            $table->dropIndex(['department_id', 'asset_type_id', 'name']);
            $table->dropConstrainedForeignId('department_id');
        });
    }
};
