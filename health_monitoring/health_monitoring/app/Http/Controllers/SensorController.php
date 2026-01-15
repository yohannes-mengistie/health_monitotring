<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use App\Events\HealthUpdateEvent;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Cache;
use App\Models\HealthData;
use Carbon\Carbon;

class SensorController extends Controller
{
    public function ingest(Request $request)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $vitals = $request->validate([
            'heart_rate'       => 'required|numeric',
            'body_temperature' => 'required|numeric',
            'device_id'        => 'required|string',
            // Optional: marker from Arduino when measurement completes
            'final'            => 'sometimes|boolean',
        ]);

        $isFinal = $request->boolean('final', false);
        $userDeviceKey = "health_monitor_{$user->id}_{$vitals['device_id']}";

        Log::info('Vitals received', [
            'user_id' => $user->id,
            'device_id' => $vitals['device_id'],
            'heart_rate' => $vitals['heart_rate'],
            'body_temperature' => $vitals['body_temperature'],
            'is_final' => $isFinal,
        ]);

        // 1. Store the latest values temporarily (always update latest)
        Cache::put("latest_vitals_{$userDeviceKey}", [
            'heart_rate'       => $vitals['heart_rate'],
            'body_temperature' => $vitals['body_temperature'],
            'timestamp'        => now()->toDateTimeString(),
        ], now()->addMinutes(5));

        // 2. If this is NOT the final packet → just acknowledge (live preview mode)
        if (!$isFinal) {
            return response()->json([
                'status' => 'received',
                'message' => 'Live data received - waiting for measurement completion',
            ]);
        }

        // ───────────────────────────────────────────────
        //          FINAL MEASUREMENT RECEIVED
        // ───────────────────────────────────────────────

        // Get the final stable values (Arduino already calculated good average/estimation)
        $finalVitals = Cache::get("latest_vitals_{$userDeviceKey}");

        if (!$finalVitals) {
            Log::warning('No recent vitals found for final processing', ['key' => $userDeviceKey]);
            return response()->json(['error' => 'No recent measurement data'], 400);
        }

        // Prepare ML payload using final values
        $mlPayload = [
            'heart_rate'       => $finalVitals['heart_rate'],
            'body_temperature' => $finalVitals['body_temperature'],
            'age'              => $user->age,
            'weight_kg'        => $user->weight,
            'height_m'         => $user->height,
            'gender'           => $user->gender,
            'patient_id'       => $user->id,
        ];

        Log::info('Processing FINAL measurement - sending to ML', $mlPayload);

        // Call ML service
        try {
            $response = Http::timeout(5)->post('http://127.0.0.1:5000/predict', $mlPayload);

            if ($response->failed()) {
                throw new \Exception("ML service returned error: " . $response->status());
            }

            $mlResult = $response->json();
            Log::info('ML prediction successful', $mlResult);
        } catch (\Exception $e) {
            Log::error('ML service failed during final processing', [
                'error' => $e->getMessage(),
                'payload' => $mlPayload
            ]);

            return response()->json([
                'error' => 'Machine Learning Service Unavailable',
                'message' => $e->getMessage()
            ], 503);
        }

        // Calculate BMI
        $bmi = $user->weight / ($user->height ** 2);

        // Get alert from ML result
        $alert = $mlResult['alert'] ?? 'normal';

        // Store the aggregated/final measurement
        $healthData = HealthData::create([
            'device_id'         => $vitals['device_id'],
            'user_id'           => $user->id,
            'heart_rate'        => $finalVitals['heart_rate'],        // final stable value
            'body_temperature'  => $finalVitals['body_temperature'],  // final stable value
            'age'               => $user->age,
            'weight_kg'         => $user->weight,
            'height_m'          => $user->height,
            'gender'            => $user->gender,
            'bmi_calculated'    => $bmi,
            'predicted_risk'    => $mlResult['predicted_risk'] ?? 'Unknown',
            'probabilities'     => json_encode($mlResult['probabilities'] ?? []),
            'alert'             => $alert,
            'timestamp'         => now(),
        ]);

        // Broadcast the final analysis to frontend
        broadcast(new HealthUpdateEvent(
            $user->id,
            $mlResult,
            [
                'heart_rate'       => $finalVitals['heart_rate'],
                'body_temperature' => $finalVitals['body_temperature'],
                'device_id'        => $vitals['device_id'],
                'is_final'         => true
            ]
        ))->toOthers();

        // Optional: clean up cache
        Cache::forget("latest_vitals_{$userDeviceKey}");

        return response()->json([
            'status' => 'success',
            'message' => 'Measurement completed and analyzed',
            'data' => [
                'final_vitals' => [
                    'heart_rate'       => $finalVitals['heart_rate'],
                    'body_temperature' => $finalVitals['body_temperature'],
                ],
                'analysis'         => $mlResult,
                'record_id'        => $healthData->id
            ]
        ]);
    }
}