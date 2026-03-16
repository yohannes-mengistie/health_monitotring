<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('health_data', function (Blueprint $table) {
            $table->id();
            $table->string('device_id')->index();
            $table->foreignId('user_id')->constrained('users')->onDelete('cascade');

            // Core Vitals
            $table->float('heart_rate', 5, 2)->nullable();
            $table->float('body_temperature', 5, 2);
            $table->integer('age');
            $table->float('weight_kg', 6, 2);
            $table->float('height_m', 4, 2);
            $table->string('gender');

            // Model Features
            $table->float('bmi', 5, 2);
            $table->float('systolic_bp', 5, 2);
            $table->float('diastolic_bp', 5, 2);
            $table->float('oxygen_saturation', 5, 2);
            $table->float('pulse_pressure', 5, 2);
            $table->float('map', 5, 2);

            // Model Outputs
            $table->string('predicted_risk');
            $table->json('probabilities')->nullable();
            $table->boolean('alert')->default(false);

            $table->timestamps(); 

            // Indexes for fast dashboard loading
            $table->index(['user_id', 'created_at']);
            $table->index('predicted_risk');
        });
    }

    public function down(): void
    {
        // Fixed: Ensure name matches the 'up' method
        Schema::dropIfExists('health_data');
    }
};
