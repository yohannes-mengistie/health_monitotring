<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use App\Events\HealthUpdateEvent;
use App\Models\HealthData;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use App\Models\User;
use App\Http\Controllers\Controller;


class SensorController extends Controller
{
    public function ingest(Request $request)
    {
        Log::debug('incoming health data', ['payload' => $request->all()]);
        // 1. Get the authenticated user (via Sanctum token)
        $user = Auth::user();

        if (!$user) {
            Log::warning('Unauthenticated request', ['headers' => $request->headers->all()]);
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        // 2. Validate incoming vitals from the Python Listener
        $vitals = $request->validate([
            'heart_rate' => 'required|numeric',
            'body_temperature' => 'required|numeric',
            'oxygen_saturation' => 'required|numeric',
        ]);
        Log::info('Vitals validated', ['vitals' => $vitals, 'user_id' => $user->id]);

        $mlPayload = [
            'heart_rate'       => (float)$vitals['heart_rate'],
            'body_temperature' => (float)$vitals['body_temperature'],
            'oxygen_saturation' => (float)$vitals['oxygen_saturation'],
            'systolic_bp'      => (float)$user->systolic_bp,
            'diastolic_bp'     => (float)$user->diastolic_bp,
            'age'              => (int)(date('Y') - date('Y', strtotime($user->dob))),
            'weight_kg'        => (float)$user->weight,
            'height_m'         => (float)$user->height,
            'gender'           => $user->gender ?? 'M',
            'patient_id'       => (int)$user->id
        ];
        Log::debug('ML Payload prepared', ['mlPayload' => $mlPayload]);
        // 4. Call the Python ML FastAPI Service
        try {
            $response = Http::timeout(3)->post('http://127.0.0.1:5000/predict', $mlPayload);

            if ($response->failed()) {
                throw new \Exception("ML Service returned an error");
            }

            $mlResult = $response->json();
            $pulsePressure = $mlResult['metrics']['pulse_pressure'] ?? null;
            $mapValue      = $mlResult['metrics']['mean_arterial_pressure'] ?? null;
            $bmi = $mlResult['metrics']['bmi'] ?? (
                $user->weight && $user->height
                ? round($user->weight / ($user->height * $user->height), 2)
                : null
            );
        } catch (\Exception $e) {
            Log::error('ML service error', [
                'error' => $e->getMessage(),
                'payload' => $request->all()
            ]);
            return response()->json([
                'error' => 'Machine Learning Service Unavailable',
                'message' => $e->getMessage()
            ], 503);
        }

        // 5. Broadcast to Frontend via WebSockets
        // We pass the User ID so the frontend can listen on a private channel
        //broadcast(new HealthUpdateEvent($user->id, $mlResult, $vitals))->toOthers();

        $healthData = HealthData::create([
            'heart_rate'       => (float)$vitals['heart_rate'],
            'body_temperature' => (float)$vitals['body_temperature'],
            'oxygen_saturation' => (float)$vitals['oxygen_saturation'],
            'systolic_bp'      => (float)$user->systolic_bp,
            'diastolic_bp'     => (float)$user->diastolic_bp,
            'age'              => (int)(date('Y') - date('Y', strtotime($user->dob))),
            'weight_kg'        => (float)$user->weight,
            'height_m'         => (float)$user->height,
            'gender'           => $user->gender ?? 'M',
            'user_id'       => (int)$user->id,
            'bmi'           =>  $bmi,
            'pulse_pressure' => $pulsePressure,
            'map'            => $mapValue,
            'device_id'      => 1,
            'predicted_risk' => $mlResult['predicted_risk'],
            'probabilities'  => $mlResult['probabilities'],
            'alert'          => $mlResult['alert']

        ]);
        Log::info('HealthData saved', ['healthData_id' => $healthData->id]);
        return response()->json([
            'status' => 'success',
            'data' => [
                'vitals' => $vitals,
                'analysis' => $mlResult
            ]
        ]);
    }

    public function getDetailedAnalysis(Request $request)
    {
        $user = Auth::user();
        $latest = HealthData::where('user_id', $user->id)->latest()->first();

        if (!$latest) {
            return response()->json(['error' => 'No data found'], 404);
        }

        try {
            $response = Http::timeout(20)->post('http://127.0.0.1:9000/generate-clinical-report', [
                'language' => $request->get('lang', 'amharic'),
                'vitals' => [
                    // MUST MATCH Python expected_features EXACTLY
                    'Heart Rate'              => (float)$latest->heart_rate,
                    'Body Temperature'       => (float)$latest->body_temperature,
                    'Oxygen Saturation'      => (float)$latest->oxygen_saturation,
                    'Systolic Blood Pressure' => (float)$latest->systolic_bp,
                    'Diastolic Blood Pressure' => (float)$latest->diastolic_bp,
                    'Age'                     => (int)$latest->age,
                    'Gender'                  => $latest->gender, // e.g., "Male"
                    'Derived_Pulse_Pressure'  => (float)$latest->pulse_pressure,
                    'Derived_BMI'             => (float)$latest->bmi,
                    'Derived_MAP'             => (float)$latest->map,
                ]
            ]);

            return response()->json($response->json());
        } catch (\Exception $e) {
            return response()->json(['error' => 'AI Service Unavailable: ' . $e->getMessage()], 503);
        }
    }

    public function getLiveStatus(Request $request)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $latest = HealthData::where('user_id', $user->id)
            ->latest('created_at')
            ->first();

        if (!$latest) {
            return response()->json([
                'status' => 'success',
                'message' => 'No live data found yet',
                'data' => [
                    'latest_vitals' => null,
                    'risk' => null,
                    'latest_recorded_at' => null,
                ],
            ]);
        }

        return response()->json([
            'status' => 'success',
            'data' => [
                'latest_vitals' => [
                    'heart_rate' => (float)$latest->heart_rate,
                    'spo2' => (float)$latest->oxygen_saturation,
                    'systolic_bp' => (float)$latest->systolic_bp,
                    'diastolic_bp' => (float)$latest->diastolic_bp,
                    'temperature' => (float)$latest->body_temperature,
                ],
                'risk' => [
                    'predicted_risk' => (string)$latest->predicted_risk,
                    'probabilities' => $latest->probabilities ?? [],
                    'alert' => (bool)$latest->alert,
                ],
                'latest_recorded_at' => $latest->created_at?->toIso8601String(),
            ],
        ]);
    }

    public function getMetricsOverview(Request $request)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $period = strtolower((string)$request->query('period', 'week'));
        $days = match ($period) {
            'day' => 1,
            'month' => 30,
            'year' => 365,
            default => 7,
        };

        $now = now();
        $currentStart = $now->copy()->subDays($days);
        $previousStart = $currentStart->copy()->subDays($days);

        $baseQuery = HealthData::where('user_id', $user->id);
        $latest = (clone $baseQuery)->latest('created_at')->first();
        if (!$latest) {
            return response()->json([
                'status' => 'success',
                'period' => $period,
                'message' => 'No health data found yet',
                'data' => [
                    'pinned_metrics' => [],
                    'other_metrics' => [],
                    'chart_points' => [],
                ],
            ]);
        }

        $current = (clone $baseQuery)
            ->whereBetween('created_at', [$currentStart, $now]);
        $previous = (clone $baseQuery)
            ->whereBetween('created_at', [$previousStart, $currentStart]);

        $currentStats = [
            'avg_heart_rate' => (float)$current->avg('heart_rate'),
            'avg_spo2' => (float)$current->avg('oxygen_saturation'),
            'avg_temperature' => (float)$current->avg('body_temperature'),
            'avg_systolic' => (float)$current->avg('systolic_bp'),
            'avg_diastolic' => (float)$current->avg('diastolic_bp'),
        ];

        $previousStats = [
            'avg_heart_rate' => (float)$previous->avg('heart_rate'),
            'avg_spo2' => (float)$previous->avg('oxygen_saturation'),
            'avg_temperature' => (float)$previous->avg('body_temperature'),
            'avg_systolic' => (float)$previous->avg('systolic_bp'),
            'avg_diastolic' => (float)$previous->avg('diastolic_bp'),
        ];

        $trend = function (float $currentValue, float $previousValue): float {
            if ($previousValue == 0.0) {
                return 0.0;
            }
            return round((($currentValue - $previousValue) / $previousValue) * 100, 2);
        };

        $chartPoints = (clone $baseQuery)
            ->whereBetween('created_at', [$currentStart, $now])
            ->orderBy('created_at')
            ->get(['created_at', 'heart_rate', 'oxygen_saturation', 'body_temperature', 'systolic_bp', 'diastolic_bp'])
            ->map(function ($row) {
                return [
                    'timestamp' => $row->created_at?->toIso8601String(),
                    'heart_rate' => (float)$row->heart_rate,
                    'spo2' => (float)$row->oxygen_saturation,
                    'temperature' => (float)$row->body_temperature,
                    'systolic_bp' => (float)$row->systolic_bp,
                    'diastolic_bp' => (float)$row->diastolic_bp,
                ];
            })
            ->values();

        return response()->json([
            'status' => 'success',
            'period' => $period,
            'data' => [
                'pinned_metrics' => [
                    [
                        'key' => 'heart_rate',
                        'label' => 'Average Heart Rate',
                        'value' => round($currentStats['avg_heart_rate'] ?: (float)$latest->heart_rate, 2),
                        'unit' => 'bpm',
                        'trend_percent' => $trend($currentStats['avg_heart_rate'], $previousStats['avg_heart_rate']),
                        'previous_value' => round($previousStats['avg_heart_rate'], 2),
                    ],
                    [
                        'key' => 'spo2',
                        'label' => 'Average SpO2',
                        'value' => round($currentStats['avg_spo2'] ?: (float)$latest->oxygen_saturation, 2),
                        'unit' => '%',
                        'trend_percent' => $trend($currentStats['avg_spo2'], $previousStats['avg_spo2']),
                        'previous_value' => round($previousStats['avg_spo2'], 2),
                    ],
                ],
                'other_metrics' => [
                    [
                        'key' => 'blood_pressure',
                        'label' => 'Blood Pressure',
                        'value' => [
                            'systolic' => (int)round($latest->systolic_bp),
                            'diastolic' => (int)round($latest->diastolic_bp),
                        ],
                        'unit' => 'mmHg',
                        'average' => [
                            'systolic' => round($currentStats['avg_systolic'], 2),
                            'diastolic' => round($currentStats['avg_diastolic'], 2),
                        ],
                    ],
                    [
                        'key' => 'temperature',
                        'label' => 'Temperature',
                        'value' => round((float)$latest->body_temperature, 2),
                        'unit' => 'C',
                        'trend_percent' => $trend($currentStats['avg_temperature'], $previousStats['avg_temperature']),
                        'previous_value' => round($previousStats['avg_temperature'], 2),
                    ],
                ],
                'chart_points' => $chartPoints,
                'latest_vitals' => [
                    'heart_rate' => (float)$latest->heart_rate,
                    'spo2' => (float)$latest->oxygen_saturation,
                    'systolic_bp' => (float)$latest->systolic_bp,
                    'diastolic_bp' => (float)$latest->diastolic_bp,
                    'temperature' => (float)$latest->body_temperature,
                ],
                'risk' => [
                    'predicted_risk' => (string)$latest->predicted_risk,
                    'probabilities' => $latest->probabilities ?? [],
                    'alert' => (bool)$latest->alert,
                ],
                'latest_recorded_at' => $latest->created_at?->toIso8601String(),
            ],
        ]);
    }

    public function update(Request $request)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $validated = $request->validate([
            'first_name' => 'sometimes|string|max:255',
            'last_name' => 'sometimes|string|max:255',
            'dob' => 'sometimes|date',
            'gender' => 'sometimes|in:male,female,other',
            'weight' => 'sometimes|numeric|min:1|max:500',
            'height' => 'sometimes|numeric|min:1|max:300',
            'systolic_bp' => 'sometimes|numeric|min:40|max:300',
            'diastolic_bp' => 'sometimes|numeric|min:30|max:250',
        ]);

        if (empty($validated)) {
            return response()->json([
                'message' => 'No valid profile fields provided',
                'data' => $user,
            ]);
        }

        $user->fill($validated);
        $user->save();

        return response()->json([
            'message' => 'Profile updated successfully',
            'data' => $user->fresh(),
        ]);
    }
}
