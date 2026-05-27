<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MeasurementSession extends Model
{
    protected $fillable = [
        'session_id',
        'user_id',
        'device_id',
        'state',
        'started_at',
        'completed_at',
        'last_seen_at',
        'last_progress',
        'last_error_code',
        'last_live',
        'last_result',
    ];

    protected $casts = [
        'started_at' => 'datetime',
        'completed_at' => 'datetime',
        'last_seen_at' => 'datetime',
        'last_live' => 'array',
        'last_result' => 'array',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
