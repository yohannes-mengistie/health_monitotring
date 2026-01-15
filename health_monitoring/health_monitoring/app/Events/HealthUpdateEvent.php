<?php
namespace App\Events;

use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class HealthUpdateEvent implements ShouldBroadcast
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public $userId;
    public $analysis;
    public $vitals;

    public function __construct($userId, $analysis, $vitals)
    {
        $this->userId = $userId;
        $this->analysis = $analysis;
        $this->vitals = $vitals;
    }

    public function broadcastOn()
    {
        // Broadcast only to the logged-in user's private channel
        return new PrivateChannel('user.' . $this->userId);
        return new Channel('public-chat');
    }
}
