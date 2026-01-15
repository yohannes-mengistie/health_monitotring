<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\User;

class RegisterController extends Controller
{
    public function index(Request $request)
    {
        $user  = $request->user();
        return response()->json([
            'message' => 'User Successfully retrived',
            'data' => $user
        ]);
    }

    public function store(Request $request)
    {
        // Validate the incoming request data
        $validatedData = $request->validate([
            'first_name' => 'required|string|max:255',
            'last_name' => 'required|string|max:255',
            'email' => 'required|string|email|max:255|unique:users',
            'password' => 'required|string|min:8|confirmed',
            'dob' => 'required|date',
            'gender' => 'required|in:male,female',
            'weight' => 'required|numeric',
            'height' => 'required|numeric',
        ]);

        // Create a new user instance
        $user  = User::create([
            'first_name' => $validatedData['first_name'],
            'last_name' => $validatedData['last_name'],
            'email' => $validatedData['email'],
            'password' => bcrypt($validatedData['password']),
            'dob' => $validatedData['dob'],
            'gender' => $validatedData['gender'],
            'weight' => $validatedData['weight'],
            'height' => $validatedData['height'],
        ]);

        return response()->json([
            'message' => 'User Successfully Registered',
            'data' => $user
        ], 201);
    }
}
