<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('clinical_assessments', function (Blueprint $table) {
            $table->string('risk_level', 20)->nullable()->after('predicted_risk');
            $table->json('structured_response')->nullable()->after('recommendation_excerpt');
            $table->string('language', 10)->nullable()->default('english')->after('structured_response');
            $table->boolean('requires_review')->default(false)->after('language');
            $table->json('vitals_snapshot')->nullable()->after('requires_review');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('clinical_assessments', function (Blueprint $table) {
            $table->dropColumn([
                'risk_level',
                'structured_response',
                'language',
                'requires_review',
                'vitals_snapshot',
            ]);
        });
    }
};
