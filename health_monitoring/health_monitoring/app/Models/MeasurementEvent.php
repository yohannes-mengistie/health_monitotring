<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MeasurementEvent extends Model
{
    protected $fillable = [
        'session_id',
        'user_id',
        'device_id',
        'type',
        'payload',
        'captured_at',
    ];

    protected $casts = [
        'payload' => 'array',
        'captured_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
