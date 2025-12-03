<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\HealthData;

class HealthMonitoringController extends Controller
{
    public function store(Request $request)
    {
        // Validate incoming request data
        $validatedData = $request->validate([
            'device_id' => 'required|string',
            'heart_rate' => 'required|integer',
            //'blood_pressure' => 'required|string',
            'temperature' => 'required|numeric',
        ]);

        // Store the validated data in the database
        $healthData = HealthData::create($validatedData);

        return response()->json([
            'message' => 'Health data recorded successfully',
            'data' => $healthData
        ], 201);

    }
}
