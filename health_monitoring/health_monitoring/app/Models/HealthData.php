<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class HealthData extends Model
{
    protected $fillable = [
        'user_id',
        'device_id',
        'heart_rate',
        'body_temperature',
        'age',
        'weight_kg',
        'height_m',
        'gender',
        'bmi_calculated',
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
