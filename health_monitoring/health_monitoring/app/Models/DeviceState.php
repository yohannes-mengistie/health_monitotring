<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class DeviceState extends Model
{
    protected $fillable = [
        'device_id',
        'user_id',
        'last_session_id',
        'state',
        'last_seen_at',
        'last_error_code',
        'last_payload',
    ];

    protected $casts = [
        'last_seen_at' => 'datetime',
        'last_payload' => 'array',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
