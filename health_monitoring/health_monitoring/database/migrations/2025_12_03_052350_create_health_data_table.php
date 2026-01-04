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
        Schema::create('health_data', function (Blueprint $table) {
            $table->id();  // Primary key
            $table->string('device_id');
            $table->foreignId('user_id')->constrained('users')->onDelete('cascade');  // Link to user profile
            $table->float('heart_rate', 5, 1)->nullable();  // e.g., 98.5
            $table->float('body_temperature', 4, 1);  // e.g., 37.8
            $table->integer('age');  // From profile, e.g., 62
            $table->float('weight_kg', 6, 2);  // e.g., 88.00
            $table->float('height_m', 4, 2);  // e.g., 1.70
            $table->string('gender');  // 'Male' or 'Female'
            $table->float('bmi_calculated', 5, 2);  // Derived, e.g., 30.4
            $table->string('predicted_risk');  // 'Low Risk', 'Medium Risk', 'High Risk'
            $table->json('probabilities')->nullable();  // e.g., {"Low Risk": 0.15, "Medium Risk": 0.70, "High Risk": 0.15}
            $table->boolean('alert')->default(false);  // True if High Risk or prob > 0.7
            $table->timestamp('timestamp')->nullable();  // When data was received
            $table->timestamps();  // created_at, updated_at

            // Indexes for fast queries
            $table->index(['user_id', 'timestamp']);  // For user timelines
            $table->index('predicted_risk');  // For risk reports
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('health_datas');
    }
};
