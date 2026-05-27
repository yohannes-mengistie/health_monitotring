<?php

namespace App\Models;

use App\Services\VitalsTrendService;
use App\Services\MetricsOverviewService;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\Eloquent\Model;

class HealthData extends Model
{
    protected static function booted(): void
    {
        static::created(function (HealthData $data) {
            app(VitalsTrendService::class)->invalidate($data->user_id);

            try {
                app(MetricsOverviewService::class)->refreshForUser($data->user_id);
            } catch (\Throwable $e) {
                Log::warning('Metrics overview refresh failed', [
                    'user_id' => $data->user_id,
                    'error' => $e->getMessage(),
                ]);
            }
        });
    }

    protected $fillable = [
        'user_id',
        'device_id',
        'heart_rate',
        'body_temperature',
        'age',
        'weight_kg',
        'height_m',
        'gender',
        'systolic_bp',
        'diastolic_bp',
        'oxygen_saturation',
        'pulse_pressure',
        'map',
        'bmi',
        'predicted_risk',
        'probabilities',
        'alert',
        'timestamp',
    ];

    protected $casts = [
        'probabilities' => 'array',
        'alert' => 'boolean',
        'timestamp' => 'datetime',
    ];

    // Relationship: Belongs to User
    public function user()
    {
        return $this->belongsTo(User::class);
    }

    // Scope: Recent records for a user
    public function scopeRecent($query, $userId, $limit = 50)
    {
        return $query->where('user_id', $userId)->orderBy('timestamp', 'desc')->limit($limit);
    }

    // Scope: High risk alerts
    public function scopeHighRisk($query)
    {
        return $query->where('alert', true)->orderBy('timestamp', 'desc');
    }
}
