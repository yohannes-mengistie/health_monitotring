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
        Schema::create('health_datas', function (Blueprint $table) {
            $table->id();
            $table->string('device_id');
            $table->decimal('heart_rate', 5, 2);
            //$table->string('blood_pressure');
            $table->decimal('temperature', 5, 2);
            $table->timestamps();
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
