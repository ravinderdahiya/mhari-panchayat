<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('departments', function (Blueprint $table) {
            $table->string('name_hi')->nullable();
        });

        Schema::table('asset_types', function (Blueprint $table) {
            $table->string('name_hi')->nullable();
        });

        Schema::table('complaint_categories', function (Blueprint $table) {
            $table->dropUnique('complaint_categories_name_unique');
            $table->string('name_hi')->nullable();
            $table->foreignId('asset_type_id')->nullable()->constrained('asset_types')->cascadeOnDelete();
            $table->foreignId('default_priority_id')->nullable()->constrained('complaint_priorities')->nullOnDelete();
            $table->index(['asset_type_id', 'name']);
        });
    }

    public function down(): void
    {
        Schema::table('complaint_categories', function (Blueprint $table) {
            $table->dropIndex(['asset_type_id', 'name']);
            $table->dropConstrainedForeignId('default_priority_id');
            $table->dropConstrainedForeignId('asset_type_id');
            $table->dropColumn('name_hi');
        });

        Schema::table('asset_types', function (Blueprint $table) {
            $table->dropColumn('name_hi');
        });

        Schema::table('departments', function (Blueprint $table) {
            $table->dropColumn('name_hi');
        });
    }
};
