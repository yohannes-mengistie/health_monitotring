<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use App\Models\HealthData;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use App\Models\User;
use App\Http\Controllers\Controller;


class SensorController extends Controller
{
    private const AGG_WINDOW_SECONDS = 15;
    private const COOLDOWN_SECONDS = 3;
    private const AGG_BUFFER_TTL_SECONDS = 120;
    private const LIVE_SAMPLE_TTL_SECONDS = 120;
    private const RECOMMENDATION_CACHE_TTL_SECONDS = 1800;

    public function ingest(Request $request)
    {
        Log::debug('incoming health data', ['payload' => $request->all()]);
        // 1. Get the authenticated user (via Sanctum token)
        /** @var User|null $user */
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

        $now = now();

        // Cache every raw sample immediately so live-status can update in near real-time.
        $liveSampleKey = "health_live_sample_user_{$user->id}";
        Cache::put($liveSampleKey, [
            'heart_rate' => (float)$vitals['heart_rate'],
            'spo2' => (float)$vitals['oxygen_saturation'],
            'temperature' => (float)$vitals['body_temperature'],
            'systolic_bp' => (float)$user->systolic_bp,
            'diastolic_bp' => (float)$user->diastolic_bp,
            'recorded_at' => $now->toIso8601String(),
        ], now()->addSeconds(self::LIVE_SAMPLE_TTL_SECONDS));

        $cacheKey = "health_ingest_buffer_user_{$user->id}";

        $buffer = Cache::get($cacheKey, [
            'phase' => 'measuring',
            'window_started_at' => $now->toIso8601String(),
            'cooldown_started_at' => null,
            'samples' => [],
        ]);

        $phase = ($buffer['phase'] ?? 'measuring') === 'cooldown' ? 'cooldown' : 'measuring';

        if ($phase === 'cooldown') {
            $cooldownStartedAt = $now;
            if (!empty($buffer['cooldown_started_at'])) {
                try {
                    $cooldownStartedAt = \Carbon\Carbon::parse($buffer['cooldown_started_at']);
                } catch (\Throwable $e) {
                    $cooldownStartedAt = $now;
                }
            }

            $cooldownElapsedSeconds = $cooldownStartedAt->diffInSeconds($now);
            if ($cooldownElapsedSeconds < self::COOLDOWN_SECONDS) {
                $cooldownRemaining = max(1, self::COOLDOWN_SECONDS - $cooldownElapsedSeconds);

                Cache::put($cacheKey, [
                    'phase' => 'cooldown',
                    'window_started_at' => $buffer['window_started_at'] ?? $now->toIso8601String(),
                    'cooldown_started_at' => $cooldownStartedAt->toIso8601String(),
                    'samples' => is_array($buffer['samples'] ?? null) ? $buffer['samples'] : [],
                ], now()->addSeconds(self::AGG_BUFFER_TTL_SECONDS));

                return response()->json([
                    'status' => 'buffering',
                    'message' => 'Measurement complete. Remove your hand and wait before re-measuring.',
                    'data' => [
                        'phase' => 'cooldown',
                        'window_seconds' => self::AGG_WINDOW_SECONDS,
                        'cooldown_seconds' => self::COOLDOWN_SECONDS,
                        'remaining_seconds' => $cooldownRemaining,
                        'samples_collected' => count(is_array($buffer['samples'] ?? null) ? $buffer['samples'] : []),
                        'ui_message' => 'Remove your hand. Wait 3 seconds, then place it again.',
                    ],
                ]);
            }

            $buffer = [
                'phase' => 'measuring',
                'window_started_at' => $now->toIso8601String(),
                'cooldown_started_at' => null,
                'samples' => [],
            ];
        }

        $windowStartedAt = $now;
        if (!empty($buffer['window_started_at'])) {
            try {
                $windowStartedAt = \Carbon\Carbon::parse($buffer['window_started_at']);
            } catch (\Throwable $e) {
                $windowStartedAt = $now;
            }
        }

        $samples = is_array($buffer['samples'] ?? null) ? $buffer['samples'] : [];
        $samples[] = [
            'heart_rate' => (float)$vitals['heart_rate'],
            'body_temperature' => (float)$vitals['body_temperature'],
            'oxygen_saturation' => (float)$vitals['oxygen_saturation'],
            'recorded_at' => $now->toIso8601String(),
        ];

        $elapsedSeconds = $windowStartedAt->diffInSeconds($now);
        if ($elapsedSeconds < self::AGG_WINDOW_SECONDS) {
            Cache::put($cacheKey, [
                'phase' => 'measuring',
                'window_started_at' => $windowStartedAt->toIso8601String(),
                'cooldown_started_at' => null,
                'samples' => $samples,
            ], now()->addSeconds(self::AGG_BUFFER_TTL_SECONDS));

            return response()->json([
                'status' => 'buffering',
                'message' => 'Sample accepted. Measuring current 15-second window.',
                'data' => [
                    'phase' => 'measuring',
                    'window_seconds' => self::AGG_WINDOW_SECONDS,
                    'cooldown_seconds' => self::COOLDOWN_SECONDS,
                    'elapsed_seconds' => $elapsedSeconds,
                    'samples_collected' => count($samples),
                    'remaining_seconds' => max(1, self::AGG_WINDOW_SECONDS - $elapsedSeconds),
                    'ui_message' => 'Measuring... keep your hand steady.',
                ],
            ]);
        }

        $averagedVitals = $this->computeAveragedVitals($samples);
        $heightMeters = $this->normalizeHeightToMeters((float)$user->height);

        // After one 15-second measurement window, switch to cooldown.
        Cache::put($cacheKey, [
            'phase' => 'cooldown',
            'window_started_at' => $windowStartedAt->toIso8601String(),
            'cooldown_started_at' => $now->toIso8601String(),
            'samples' => [],
        ], now()->addSeconds(self::AGG_BUFFER_TTL_SECONDS));

        $mlPayload = [
            'heart_rate'       => $averagedVitals['heart_rate'],
            'body_temperature' => $averagedVitals['body_temperature'],
            'oxygen_saturation' => $averagedVitals['oxygen_saturation'],
            'systolic_bp'      => (float)$user->systolic_bp,
            'diastolic_bp'     => (float)$user->diastolic_bp,
            'age'              => (int)(date('Y') - date('Y', strtotime($user->dob))),
            'weight_kg'        => (float)$user->weight,
            'height_m'         => $heightMeters,
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
                $user->weight && $heightMeters > 0
                ? round($user->weight / ($heightMeters * $heightMeters), 2)
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

        $feedbackResult = null;
        try {
            $feedbackPayload = [
                'language' => 'english',
                'scenario_name' => 'Live 15-second average',
                'vitals' => [
                    'Heart Rate' => $averagedVitals['heart_rate'],
                    'Body Temperature' => $averagedVitals['body_temperature'],
                    'Oxygen Saturation' => $averagedVitals['oxygen_saturation'],
                    'Systolic Blood Pressure' => (float)$user->systolic_bp,
                    'Diastolic Blood Pressure' => (float)$user->diastolic_bp,
                    'Age' => (int)(date('Y') - date('Y', strtotime($user->dob))),
                    'Gender' => $user->gender ?? 'M',
                    'Derived_Pulse_Pressure' => (float)($pulsePressure ?? 0),
                    'Derived_BMI' => (float)($bmi ?? 0),
                    'Derived_MAP' => (float)($mapValue ?? 0),
                ],
            ];

            $feedbackResponse = Http::timeout(8)->post('http://127.0.0.1:9000/generate-clinical-report', $feedbackPayload);
            if ($feedbackResponse->successful()) {
                $feedbackResult = $feedbackResponse->json();
            } else {
                Log::warning('Feedback service returned non-success', [
                    'status' => $feedbackResponse->status(),
                    'body' => $feedbackResponse->body(),
                ]);
            }
        } catch (\Throwable $e) {
            Log::warning('Feedback service call failed', [
                'error' => $e->getMessage(),
            ]);
        }

        // 5. Broadcast to Frontend via WebSockets
        // We pass the User ID so the frontend can listen on a private channel
        //broadcast(new HealthUpdateEvent($user->id, $mlResult, $vitals))->toOthers();

        $healthData = HealthData::create([
            'heart_rate'       => $averagedVitals['heart_rate'],
            'body_temperature' => $averagedVitals['body_temperature'],
            'oxygen_saturation' => $averagedVitals['oxygen_saturation'],
            'systolic_bp'      => (float)$user->systolic_bp,
            'diastolic_bp'     => (float)$user->diastolic_bp,
            'age'              => (int)(date('Y') - date('Y', strtotime($user->dob))),
            'weight_kg'        => (float)$user->weight,
            'height_m'         => $heightMeters,
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

        if (is_array($feedbackResult)) {
            $cacheKey = $this->recommendationCacheKey((int)$user->id, (int)$healthData->id, 'english');
            Cache::put($cacheKey, $feedbackResult, now()->addSeconds(self::RECOMMENDATION_CACHE_TTL_SECONDS));
        }

        Log::info('HealthData saved', ['healthData_id' => $healthData->id]);
        return response()->json([
            'status' => 'success',
            'data' => [
                'window' => [
                    'seconds' => self::AGG_WINDOW_SECONDS,
                    'samples_used' => count($samples),
                ],
                'cycle' => [
                    'phase' => 'cooldown',
                    'remaining_seconds' => self::COOLDOWN_SECONDS,
                    'ui_message' => 'Measurement complete. Remove your hand and wait 3 seconds.',
                ],
                'vitals' => $averagedVitals,
                'analysis' => $mlResult,
                'recommendation' => $feedbackResult,
            ]
        ]);
    }

    private function computeAveragedVitals(array $samples): array
    {
        $count = max(count($samples), 1);
        $heartRateSum = 0.0;
        $temperatureSum = 0.0;
        $spo2Sum = 0.0;

        foreach ($samples as $sample) {
            $heartRateSum += (float)($sample['heart_rate'] ?? 0);
            $temperatureSum += (float)($sample['body_temperature'] ?? 0);
            $spo2Sum += (float)($sample['oxygen_saturation'] ?? 0);
        }

        return [
            'heart_rate' => round($heartRateSum / $count, 2),
            'body_temperature' => round($temperatureSum / $count, 2),
            'oxygen_saturation' => round($spo2Sum / $count, 2),
        ];
    }

    private function normalizeHeightToMeters(float $rawHeight): float
    {
        if ($rawHeight <= 0) {
            return 0.0;
        }

        // Mobile app profile forms send height in centimeters.
        if ($rawHeight > 3) {
            return round($rawHeight / 100, 2);
        }

        return round($rawHeight, 2);
    }

    public function getDetailedAnalysis(Request $request)
    {
        /** @var User|null $user */
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $latest = HealthData::where('user_id', $user->id)->latest()->first();

        if (!$latest) {
            return response()->json(['error' => 'No data found'], 404);
        }

        $language = strtolower((string)$request->get('lang', 'amharic'));
        $language = str_starts_with($language, 'am') ? 'amharic' : 'english';
        $cacheKey = $this->recommendationCacheKey((int)$user->id, (int)$latest->id, $language);

        $cachedReport = Cache::get($cacheKey);
        if (is_array($cachedReport)) {
            return response()->json([
                ...$cachedReport,
                'source' => 'cache',
            ]);
        }

        try {
            $response = Http::timeout(12)->post('http://127.0.0.1:9000/generate-clinical-report', [
                'language' => $language,
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

            $reportPayload = $response->json();
            if (is_array($reportPayload)) {
                Cache::put($cacheKey, $reportPayload, now()->addSeconds(self::RECOMMENDATION_CACHE_TTL_SECONDS));
            }

            return response()->json([
                ...$reportPayload,
                'source' => 'fresh',
            ]);
        } catch (\Exception $e) {
            return response()->json(['error' => 'AI Service Unavailable: ' . $e->getMessage()], 503);
        }
    }

    private function recommendationCacheKey(int $userId, int $healthDataId, string $language): string
    {
        return "health_recommendation:user:{$userId}:record:{$healthDataId}:lang:{$language}";
    }

    public function getLiveStatus(Request $request)
    {
        /** @var User|null $user */
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $liveSampleKey = "health_live_sample_user_{$user->id}";
        $liveSample = Cache::get($liveSampleKey);
        $cycleState = $this->resolveCycleState((int)$user->id);

        $latest = HealthData::where('user_id', $user->id)
            ->latest('created_at')
            ->first();

        if (!$latest && !$liveSample) {
            return response()->json([
                'status' => 'success',
                'message' => 'No live data found yet',
                'data' => [
                    'latest_vitals' => null,
                    'risk' => null,
                    'latest_recorded_at' => null,
                    ...$cycleState,
                ],
            ]);
        }

        if ($liveSample) {
            return response()->json([
                'status' => 'success',
                'data' => [
                    'latest_vitals' => [
                        'heart_rate' => (float)($liveSample['heart_rate'] ?? 0),
                        'spo2' => (float)($liveSample['spo2'] ?? 0),
                        'systolic_bp' => (float)($liveSample['systolic_bp'] ?? 0),
                        'diastolic_bp' => (float)($liveSample['diastolic_bp'] ?? 0),
                        'temperature' => (float)($liveSample['temperature'] ?? 0),
                    ],
                    'risk' => [
                        'predicted_risk' => (string)($latest->predicted_risk ?? 'unknown'),
                        'probabilities' => $latest->probabilities ?? [],
                        'alert' => (bool)($latest->alert ?? false),
                    ],
                    'latest_recorded_at' => $liveSample['recorded_at'] ?? $latest?->created_at?->toIso8601String(),
                    'source' => 'raw_live_sample',
                    ...$cycleState,
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
                'source' => 'averaged_db',
                ...$cycleState,
            ],
        ]);
    }

    private function resolveCycleState(int $userId): array
    {
        $now = now();
        $cacheKey = "health_ingest_buffer_user_{$userId}";

        $buffer = Cache::get($cacheKey, [
            'phase' => 'measuring',
            'window_started_at' => $now->toIso8601String(),
            'cooldown_started_at' => null,
            'samples' => [],
        ]);

        $phase = ($buffer['phase'] ?? 'measuring') === 'cooldown' ? 'cooldown' : 'measuring';

        if ($phase === 'cooldown') {
            $cooldownStartedAt = $now;
            if (!empty($buffer['cooldown_started_at'])) {
                try {
                    $cooldownStartedAt = \Carbon\Carbon::parse($buffer['cooldown_started_at']);
                } catch (\Throwable $e) {
                    $cooldownStartedAt = $now;
                }
            }

            $cooldownElapsedSeconds = $cooldownStartedAt->diffInSeconds($now);
            if ($cooldownElapsedSeconds < self::COOLDOWN_SECONDS) {
                return [
                    'phase' => 'cooldown',
                    'remaining_seconds' => max(1, self::COOLDOWN_SECONDS - $cooldownElapsedSeconds),
                    'ui_message' => 'Remove your hand. Wait 3 seconds, then place it again.',
                ];
            }

            return [
                'phase' => 'measuring',
                'remaining_seconds' => self::AGG_WINDOW_SECONDS,
                'ui_message' => 'Measuring... keep your hand steady.',
            ];
        }

        $windowStartedAt = $now;
        if (!empty($buffer['window_started_at'])) {
            try {
                $windowStartedAt = \Carbon\Carbon::parse($buffer['window_started_at']);
            } catch (\Throwable $e) {
                $windowStartedAt = $now;
            }
        }

        $elapsedSeconds = $windowStartedAt->diffInSeconds($now);
        $remainingSeconds = max(1, self::AGG_WINDOW_SECONDS - $elapsedSeconds);

        return [
            'phase' => 'measuring',
            'remaining_seconds' => $remainingSeconds,
            'ui_message' => 'Measuring... keep your hand steady.',
        ];
    }

    public function getMetricsOverview(Request $request)
    {
        /** @var User|null $user */
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
                    'health_score' => [
                        'value' => 0,
                        'label' => 'No Data',
                    ],
                    'insights' => [],
                    'summary_statistics' => [],
                    'range_coverage' => [],
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

        $currentRows = (clone $baseQuery)
            ->whereBetween('created_at', [$currentStart, $now])
            ->orderBy('created_at')
            ->get(['created_at', 'heart_rate', 'oxygen_saturation', 'body_temperature', 'systolic_bp', 'diastolic_bp']);

        $chartPoints = $currentRows
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

        $heartRateValues = $currentRows->pluck('heart_rate')->map(fn($value) => (float)$value)->values()->all();
        $spo2Values = $currentRows->pluck('oxygen_saturation')->map(fn($value) => (float)$value)->values()->all();
        $temperatureValues = $currentRows->pluck('body_temperature')->map(fn($value) => (float)$value)->values()->all();
        $systolicValues = $currentRows->pluck('systolic_bp')->map(fn($value) => (float)$value)->values()->all();
        $diastolicValues = $currentRows->pluck('diastolic_bp')->map(fn($value) => (float)$value)->values()->all();

        $summaryStatistics = [
            'heart_rate' => $this->buildMetricStatistics($heartRateValues, 'bpm'),
            'spo2' => $this->buildMetricStatistics($spo2Values, '%'),
            'temperature' => $this->buildMetricStatistics($temperatureValues, 'C'),
            'systolic_bp' => $this->buildMetricStatistics($systolicValues, 'mmHg'),
            'diastolic_bp' => $this->buildMetricStatistics($diastolicValues, 'mmHg'),
        ];

        $rangeCoverage = [
            'heart_rate' => $this->calculateRangeCoverage($heartRateValues, 60, 100),
            'spo2' => $this->calculateRangeCoverage($spo2Values, 95, 100),
            'temperature' => $this->calculateRangeCoverage($temperatureValues, 36.1, 37.5),
            'systolic_bp' => $this->calculateRangeCoverage($systolicValues, 90, 130),
            'diastolic_bp' => $this->calculateRangeCoverage($diastolicValues, 60, 85),
        ];

        $healthScoreValue = $this->calculateHealthScore($summaryStatistics, (string)$latest->predicted_risk);
        $healthScoreLabel = match (true) {
            $healthScoreValue >= 90 => 'Excellent Health',
            $healthScoreValue >= 75 => 'Good Health',
            $healthScoreValue >= 60 => 'Fair Health',
            default => 'Needs Attention',
        };

        $insights = $this->buildInsights(
            $summaryStatistics,
            $rangeCoverage,
            $period,
            $currentStats,
            $previousStats
        );

        return response()->json([
            'status' => 'success',
            'period' => $period,
            'data' => [
                'health_score' => [
                    'value' => $healthScoreValue,
                    'label' => $healthScoreLabel,
                ],
                'insights' => $insights,
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
                'summary_statistics' => $summaryStatistics,
                'range_coverage' => $rangeCoverage,
                'comparison' => [
                    'current' => $currentStats,
                    'previous' => $previousStats,
                ],
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

    private function buildMetricStatistics(array $values, string $unit): array
    {
        if (empty($values)) {
            return [
                'avg' => 0.0,
                'min' => 0.0,
                'max' => 0.0,
                'std_dev' => 0.0,
                'count' => 0,
                'unit' => $unit,
            ];
        }

        $count = count($values);
        $avg = array_sum($values) / $count;
        $variance = 0.0;
        foreach ($values as $value) {
            $variance += pow(((float)$value - $avg), 2);
        }

        $stdDev = sqrt($variance / $count);

        return [
            'avg' => round($avg, 2),
            'min' => round(min($values), 2),
            'max' => round(max($values), 2),
            'std_dev' => round($stdDev, 2),
            'count' => $count,
            'unit' => $unit,
        ];
    }

    private function calculateRangeCoverage(array $values, float $min, float $max): float
    {
        if (empty($values)) {
            return 0.0;
        }

        $inRange = 0;
        foreach ($values as $value) {
            $asFloat = (float)$value;
            if ($asFloat >= $min && $asFloat <= $max) {
                $inRange++;
            }
        }

        return round(($inRange / count($values)) * 100, 2);
    }

    private function calculateHealthScore(array $stats, string $riskLabel): int
    {
        $score = 100.0;

        $avgHr = (float)($stats['heart_rate']['avg'] ?? 0.0);
        $avgSpo2 = (float)($stats['spo2']['avg'] ?? 0.0);
        $avgTemp = (float)($stats['temperature']['avg'] ?? 0.0);
        $avgSys = (float)($stats['systolic_bp']['avg'] ?? 0.0);
        $avgDia = (float)($stats['diastolic_bp']['avg'] ?? 0.0);

        if ($avgSpo2 > 0 && $avgSpo2 < 95) {
            $score -= (95 - $avgSpo2) * 3.5;
        }

        if ($avgHr > 0 && ($avgHr < 60 || $avgHr > 100)) {
            $targetHr = $avgHr < 60 ? 60 : 100;
            $score -= abs($avgHr - $targetHr) * 0.9;
        }

        if ($avgTemp > 0 && ($avgTemp < 36.1 || $avgTemp > 37.5)) {
            $targetTemp = $avgTemp < 36.1 ? 36.1 : 37.5;
            $score -= abs($avgTemp - $targetTemp) * 18;
        }

        if ($avgSys > 130) {
            $score -= ($avgSys - 130) * 0.45;
        }

        if ($avgDia > 85) {
            $score -= ($avgDia - 85) * 0.6;
        }

        $risk = strtolower($riskLabel);
        if (str_contains($risk, 'critical')) {
            $score -= 35;
        } elseif (str_contains($risk, 'high')) {
            $score -= 20;
        } elseif (str_contains($risk, 'moderate') || str_contains($risk, 'medium')) {
            $score -= 10;
        }

        return (int)max(0, min(100, round($score)));
    }

    private function buildInsights(
        array $summaryStatistics,
        array $rangeCoverage,
        string $period,
        array $currentStats,
        array $previousStats
    ): array {
        $periodLabel = ucfirst($period);

        $bestSpo2 = (float)($summaryStatistics['spo2']['max'] ?? 0.0);
        $avgHr = (float)($summaryStatistics['heart_rate']['avg'] ?? 0.0);
        $hrStdDev = (float)($summaryStatistics['heart_rate']['std_dev'] ?? 0.0);
        $normalRange = round((
            (float)($rangeCoverage['heart_rate'] ?? 0.0) +
            (float)($rangeCoverage['spo2'] ?? 0.0) +
            (float)($rangeCoverage['temperature'] ?? 0.0) +
            (float)($rangeCoverage['systolic_bp'] ?? 0.0) +
            (float)($rangeCoverage['diastolic_bp'] ?? 0.0)
        ) / 5, 2);

        $hrTrend = 0.0;
        if ((float)$previousStats['avg_heart_rate'] !== 0.0) {
            $hrTrend = round((((float)$currentStats['avg_heart_rate'] - (float)$previousStats['avg_heart_rate']) / (float)$previousStats['avg_heart_rate']) * 100, 2);
        }

        return [
            [
                'key' => 'best_spo2',
                'title' => "Best SpO2 this {$periodLabel}",
                'value' => round($bestSpo2, 1),
                'unit' => '%',
                'description' => $bestSpo2 >= 97
                    ? 'Excellent oxygen stability in your readings.'
                    : 'SpO2 peaked lower than ideal. Continue steady breathing and recheck sensor fit.',
            ],
            [
                'key' => 'avg_heart_rate',
                'title' => "Average Heart Rate ({$periodLabel})",
                'value' => round($avgHr, 1),
                'unit' => 'bpm',
                'description' => $hrTrend <= 0
                    ? 'Heart rate trend is stable or improving versus previous period.'
                    : 'Heart rate trend is rising; watch hydration and stress levels.',
            ],
            [
                'key' => 'time_in_normal_range',
                'title' => 'Time in Normal Range',
                'value' => $normalRange,
                'unit' => '%',
                'description' => $normalRange >= 90
                    ? 'Most readings stayed within healthy thresholds.'
                    : 'Some readings moved outside normal thresholds. Review trend charts below.',
            ],
            [
                'key' => 'heart_rate_variability_proxy',
                'title' => 'Heart Rate Consistency',
                'value' => round($hrStdDev, 2),
                'unit' => 'std dev',
                'description' => $hrStdDev <= 6
                    ? 'Heart rate variation is calm and consistent.'
                    : 'Higher variation detected. Consider rest before next measurement cycle.',
            ],
        ];
    }

    public function update(Request $request)
    {
        /** @var User|null $user */
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
