<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_states', function (Blueprint $table) {
            $table->id();
            $table->string('device_id', 64)->unique();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('last_session_id', 64)->nullable();
            $table->string('state', 40)->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->string('last_error_code', 80)->nullable();
            $table->json('last_payload')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_states');
    }
};
