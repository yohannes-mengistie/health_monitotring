<?php
use App\Models\User;
use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('App.Models.User.{id}', function ($user, $id) {
    return (int) $user->id === (int) $id;
});

// Broadcast::channel('user.{id}', function ($user, $id) {
//     // Only allow the user to listen to their own private health channel
//     return (int) $user->id === (int) $id;
// });
