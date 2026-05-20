<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('clinical_assessments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->onDelete('cascade');
            $table->string('source_endpoint', 64)->default('health/analysis-v2');

            $table->string('symptom_key', 100)->nullable();
            $table->string('symptom_label', 120)->nullable();
            $table->unsignedTinyInteger('severity')->nullable();
            $table->boolean('high_risk')->default(false);
            $table->boolean('red_flag_yes')->nullable();
            $table->string('medication_taken_today', 20)->nullable();

            $table->json('known_conditions')->nullable();
            $table->json('opqrst')->nullable();
            $table->json('structured_assessment')->nullable();

            $table->boolean('ai_success')->nullable();
            $table->string('ai_model', 100)->nullable();
            $table->string('predicted_risk', 50)->nullable();
            $table->text('recommendation_excerpt')->nullable();

            $table->timestamps();

            $table->index(['user_id', 'created_at']);
            $table->index(['user_id', 'symptom_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('clinical_assessments');
    }
};
