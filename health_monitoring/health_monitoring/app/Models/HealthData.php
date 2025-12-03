<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class HealthData extends Model
{
    protected $fillable = [
        'device_id',
        'heart_rate',
        //'blood_pressure',
        'temperature',
    ];

    protected $casts = [
        'heart_rate' => 'decimal:2',
        'temperature' => 'decimal:2',
    ];
}
