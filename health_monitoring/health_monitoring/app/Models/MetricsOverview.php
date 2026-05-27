<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MetricsOverview extends Model
{
    protected $fillable = [
        'user_id',
        'period',
        'data',
        'computed_at',
    ];

    protected $casts = [
        'data' => 'array',
        'computed_at' => 'datetime',
    ];
}
