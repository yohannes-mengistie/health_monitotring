<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('measurement_sessions', function (Blueprint $table) {
            $table->id();
            $table->string('session_id', 64)->unique();
            $table->foreignId('user_id')->constrained('users')->onDelete('cascade');
            $table->string('device_id', 64)->index();
            $table->string('state', 40)->default('WAITING_FOR_FINGER');
            $table->timestamp('started_at')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->unsignedSmallInteger('last_progress')->nullable();
            $table->string('last_error_code', 80)->nullable();
            $table->json('last_live')->nullable();
            $table->json('last_result')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'created_at']);
            $table->index(['device_id', 'state']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('measurement_sessions');
    }
};
