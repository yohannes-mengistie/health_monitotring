<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use App\Models\HealthData;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use App\Services\MetricsOverviewService;
use App\Models\User;
use App\Http\Controllers\Controller;


class SensorController extends Controller
{
    private const AGG_WINDOW_SECONDS = 15;
    private const COOLDOWN_SECONDS = 3;
    private const AGG_BUFFER_TTL_SECONDS = 120;
    private const LIVE_SAMPLE_TTL_SECONDS = 120;
    private const RECOMMENDATION_CACHE_TTL_SECONDS = 1800;
    private const MODEL_HIGH_RISK_THRESHOLD = 0.3;

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
            'heart_rate'        => 'required|numeric',
            'body_temperature'  => 'required|numeric',
            'oxygen_saturation' => 'required|numeric',
            'systolic_bp'       => 'sometimes|numeric|min:40|max:300',
            'diastolic_bp'      => 'sometimes|numeric|min:30|max:250',
        ]);
        Log::info('Vitals validated', ['vitals' => $vitals, 'user_id' => $user->id]);

        $systolicBp  = array_key_exists('systolic_bp', $vitals)
            ? (float) $vitals['systolic_bp']
            : (float) $user->systolic_bp;
        $diastolicBp = array_key_exists('diastolic_bp', $vitals)
            ? (float) $vitals['diastolic_bp']
            : (float) $user->diastolic_bp;

        $now = now();

        // Cache every raw sample immediately so live-status can update in near real-time.
        $liveSampleKey = "health_live_sample_user_{$user->id}";
        Cache::put($liveSampleKey, [
            'heart_rate'   => (float) $vitals['heart_rate'],
            'spo2'         => (float) $vitals['oxygen_saturation'],
            'temperature'  => (float) $vitals['body_temperature'],
            'systolic_bp'  => $systolicBp,
            'diastolic_bp' => $diastolicBp,
            'recorded_at'  => $now->toIso8601String(),
        ], now()->addSeconds(self::LIVE_SAMPLE_TTL_SECONDS));

        $cacheKey = "health_ingest_buffer_user_{$user->id}";

        $buffer = Cache::get($cacheKey, [
            'phase'               => 'measuring',
            'window_started_at'   => $now->toIso8601String(),
            'cooldown_started_at' => null,
            'samples'             => [],
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
                    'phase'               => 'cooldown',
                    'window_started_at'   => $buffer['window_started_at'] ?? $now->toIso8601String(),
                    'cooldown_started_at' => $cooldownStartedAt->toIso8601String(),
                    'samples'             => is_array($buffer['samples'] ?? null) ? $buffer['samples'] : [],
                ], now()->addSeconds(self::AGG_BUFFER_TTL_SECONDS));

                return response()->json([
                    'status'  => 'buffering',
                    'message' => 'Measurement complete. Remove your hand and wait before re-measuring.',
                    'data'    => [
                        'phase'            => 'cooldown',
                        'window_seconds'   => self::AGG_WINDOW_SECONDS,
                        'cooldown_seconds' => self::COOLDOWN_SECONDS,
                        'remaining_seconds' => $cooldownRemaining,
                        'samples_collected' => count(is_array($buffer['samples'] ?? null) ? $buffer['samples'] : []),
                        'ui_message'        => 'Remove your hand. Wait 3 seconds, then place it again.',
                    ],
                ]);
            }

            $buffer = [
                'phase'               => 'measuring',
                'window_started_at'   => $now->toIso8601String(),
                'cooldown_started_at' => null,
                'samples'             => [],
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

        $samples   = is_array($buffer['samples'] ?? null) ? $buffer['samples'] : [];
        $samples[] = [
            'heart_rate'       => (float) $vitals['heart_rate'],
            'body_temperature' => (float) $vitals['body_temperature'],
            'oxygen_saturation' => (float) $vitals['oxygen_saturation'],
            'recorded_at'      => $now->toIso8601String(),
        ];

        $elapsedSeconds = $windowStartedAt->diffInSeconds($now);
        if ($elapsedSeconds < self::AGG_WINDOW_SECONDS) {
            Cache::put($cacheKey, [
                'phase'               => 'measuring',
                'window_started_at'   => $windowStartedAt->toIso8601String(),
                'cooldown_started_at' => null,
                'samples'             => $samples,
            ], now()->addSeconds(self::AGG_BUFFER_TTL_SECONDS));

            return response()->json([
                'status'  => 'buffering',
                'message' => 'Sample accepted. Measuring current 15-second window.',
                'data'    => [
                    'phase'             => 'measuring',
                    'window_seconds'    => self::AGG_WINDOW_SECONDS,
                    'cooldown_seconds'  => self::COOLDOWN_SECONDS,
                    'elapsed_seconds'   => $elapsedSeconds,
                    'samples_collected' => count($samples),
                    'remaining_seconds' => max(1, self::AGG_WINDOW_SECONDS - $elapsedSeconds),
                    'ui_message'        => 'Measuring... keep your hand steady.',
                ],
            ]);
        }

        $averagedVitals = $this->computeAveragedVitals($samples);

        // After one 15-second measurement window, switch to cooldown.
        Cache::put($cacheKey, [
            'phase'               => 'cooldown',
            'window_started_at'   => $windowStartedAt->toIso8601String(),
            'cooldown_started_at' => $now->toIso8601String(),
            'samples'             => [],
        ], now()->addSeconds(self::AGG_BUFFER_TTL_SECONDS));

        // ── Compute derived metrics locally (new model doesn't need them as features)
        $pulsePressure = round($systolicBp - $diastolicBp, 2);
        $mapValue      = round($diastolicBp + ($pulsePressure / 3), 2);
        $bmi           = ($user->weight && $user->height > 0)
            ? round($user->weight / pow($user->height / 100, 2), 2)
            : null;

        // ── Gender: 'M' or 'F' ───────────────────────────────
        $genderCode = strtoupper(substr($user->gender ?? 'M', 0, 1));

        // ── ML Payload — 7 features matching FastAPI SensorData ──
        $mlPayload = [
            'heart_rate'   => (float) $averagedVitals['heart_rate'],
            'spo2'         => (float) $averagedVitals['oxygen_saturation'],
            'temperature'  => (float) $averagedVitals['body_temperature'],
            'systolic_bp'  => (float) $systolicBp,
            'diastolic_bp' => (float) $diastolicBp,
            'age'          => (int) (date('Y') - date('Y', strtotime($user->dob))),
            'gender'       => $genderCode,
            'patient_id'   => (int) $user->id,
            // ❌ NO weight_kg
            // ❌ NO height_m
            // ❌ NO body_temperature
            // ❌ NO oxygen_saturation
        ];
        Log::debug('ML Payload prepared', ['mlPayload' => $mlPayload]);

        // 4. Call the Python ML FastAPI Service
        try {
            $response = Http::timeout((int) config('services.ml.timeout', 3))
                ->post(rtrim(config('services.ml.url'), '/') . '/predict', $mlPayload);

            if ($response->failed()) {
                throw new \Exception("ML Service returned an error");
            }

            $mlResult = $response->json();
        } catch (\Exception $e) {
            Log::error('ML service error', [
                'error'   => $e->getMessage(),
                'payload' => $mlPayload,
            ]);
            return response()->json([
                'error'   => 'Machine Learning Service Unavailable',
                'message' => $e->getMessage(),
            ], 503);
        }

        // 5. Call the Feedback / Clinical Report Service
        $feedbackResult = null;
        try {
            $feedbackPayload = [
                'language'      => 'english',
                'scenario_name' => 'Live 15-second average',
                'vitals'        => [
                    'Heart Rate'               => $averagedVitals['heart_rate'],
                    'Body Temperature'         => $averagedVitals['body_temperature'],
                    'Oxygen Saturation'        => $averagedVitals['oxygen_saturation'],
                    'Systolic Blood Pressure'  => $systolicBp,
                    'Diastolic Blood Pressure' => $diastolicBp,
                    'Age'                      => (int) (date('Y') - date('Y', strtotime($user->dob))),
                    'Gender'                   => $user->gender ?? 'M',
                    'Derived_Pulse_Pressure'   => $pulsePressure,
                    'Derived_BMI'              => (float) ($bmi ?? 0),
                    'Derived_MAP'              => $mapValue,
                ],
            ];

            $feedbackResponse = Http::timeout((int) config('services.feedback.timeout', 8))
                ->post(rtrim(config('services.feedback.url'), '/') . '/generate-clinical-report', $feedbackPayload);
            if ($feedbackResponse->successful()) {
                $feedbackResult = $feedbackResponse->json();
            } else {
                Log::warning('Feedback service returned non-success', [
                    'status' => $feedbackResponse->status(),
                    'body'   => $feedbackResponse->body(),
                ]);
            }
        } catch (\Throwable $e) {
            Log::warning('Feedback service call failed', ['error' => $e->getMessage()]);
        }

        $finalRisk = (string) ($mlResult['predicted_risk'] ?? 'unknown');

        // 7. Persist to database
        $healthData = HealthData::create([
            'heart_rate'        => $averagedVitals['heart_rate'],
            'body_temperature'  => $averagedVitals['body_temperature'],
            'oxygen_saturation' => $averagedVitals['oxygen_saturation'],
            'systolic_bp'       => $systolicBp,
            'diastolic_bp'      => $diastolicBp,
            'age'               => (int) (date('Y') - date('Y', strtotime($user->dob))),
            'gender'            => $user->gender ?? 'M',
            'bmi'               => $bmi,
            'pulse_pressure'    => $pulsePressure,
            'map'               => $mapValue,
            'device_id'         => 1,
            'user_id'           => (int) $user->id,
            'predicted_risk'    => $finalRisk,
            'probabilities'     => $mlResult['probabilities'],
            'alert'             => $finalRisk === 'High',   // new model uses 'High' not 'High Risk'
        ]);


        if (is_array($feedbackResult)) {
            $recCacheKey = $this->recommendationCacheKey((int) $user->id, (int) $healthData->id, 'english');
            Cache::put($recCacheKey, $feedbackResult, now()->addSeconds(self::RECOMMENDATION_CACHE_TTL_SECONDS));
        }

        Log::info('HealthData saved', ['healthData_id' => $healthData->id]);

        return response()->json([
            'status' => 'success',
            'data'   => [
                'window' => [
                    'seconds'      => self::AGG_WINDOW_SECONDS,
                    'samples_used' => count($samples),
                ],
                'cycle' => [
                    'phase'             => 'cooldown',
                    'remaining_seconds' => self::COOLDOWN_SECONDS,
                    'ui_message'        => 'Measurement complete. Remove your hand and wait 3 seconds.',
                ],
                'vitals'   => $averagedVitals,
                'analysis' => [
                    ...$mlResult,
                    'model_predicted_risk' => $mlResult['predicted_risk'] ?? null,
                    'predicted_risk'       => $finalRisk,
                    'metrics' => [
                        'pulse_pressure'        => $pulsePressure,
                        'mean_arterial_pressure' => $mapValue,
                        'bmi'                   => $bmi,
                    ],
                ],
                'recommendation' => $feedbackResult,
            ],
        ]);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // WHO Safety Layer
    // New model returns 'High' / 'Medium' / 'Low'
    // ──────────────────────────────────────────────────────────────────────────
    private function applyWhoSafetyLayer(
        string $modelRisk,
        array  $averagedVitals,
        float  $systolicBp,
        float  $diastolicBp,
        float  $mapValue
    ): string {
        $heartRate   = (float) ($averagedVitals['heart_rate'] ?? 0);
        $temperature = (float) ($averagedVitals['body_temperature'] ?? 0);
        $spo2        = (float) ($averagedVitals['oxygen_saturation'] ?? 0);

        $redFlags = (
            $spo2        <  92   ||
            $systolicBp  <  90   ||
            $mapValue    <  65   ||
            $temperature >= 38.5 ||
            $temperature <= 35.0 ||
            $heartRate   <  45   ||
            $heartRate   >  120
        );

        $stable = (
            $spo2        >= 95  &&
            $heartRate   >= 60  && $heartRate   <= 100 &&
            $systolicBp  >= 100 && $systolicBp  <= 140 &&
            $diastolicBp >= 60  && $diastolicBp <= 90  &&
            $temperature >= 36.0 && $temperature <= 37.5 &&
            $mapValue    >= 70
        );

        // Downgrade: model says 'High' but vitals look stable → 'Medium'
        if (strtolower($modelRisk) === 'high' && $stable && !$redFlags) {
            return 'Medium';
        }

        // Upgrade: model says 'Low' or 'Medium' but red flags present → 'High'
        if (strtolower($modelRisk) !== 'high' && $redFlags) {
            return 'High';
        }

        return $modelRisk;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Compute averaged vitals from buffer samples
    // ──────────────────────────────────────────────────────────────────────────
    private function computeAveragedVitals(array $samples): array
    {
        $count           = max(count($samples), 1);
        $heartRateSum    = 0.0;
        $temperatureSum  = 0.0;
        $spo2Sum         = 0.0;

        foreach ($samples as $sample) {
            $heartRateSum   += (float) ($sample['heart_rate'] ?? 0);
            $temperatureSum += (float) ($sample['body_temperature'] ?? 0);
            $spo2Sum        += (float) ($sample['oxygen_saturation'] ?? 0);
        }

        return [
            'heart_rate'       => round($heartRateSum / $count, 2),
            'body_temperature' => round($temperatureSum / $count, 2),
            'oxygen_saturation' => round($spo2Sum / $count, 2),
        ];
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Detailed Analysis (Recommendation Report)
    // ──────────────────────────────────────────────────────────────────────────
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

        $language = strtolower((string) $request->get('lang', 'amharic'));
        $language = str_starts_with($language, 'am') ? 'amharic' : 'english';
        $cacheKey = $this->recommendationCacheKey((int) $user->id, (int) $latest->id, $language);

        $cachedReport = Cache::get($cacheKey);
        if (is_array($cachedReport)) {
            return response()->json([...$cachedReport, 'source' => 'cache']);
        }

        try {
            $pulsePressure = round((float) $latest->systolic_bp - (float) $latest->diastolic_bp, 2);
            $mapValue      = round((float) $latest->diastolic_bp + ($pulsePressure / 3), 2);

            $response = Http::timeout(12)->post(rtrim(config('services.feedback.url'), '/') . '/generate-clinical-report', [
                'language' => $language,
                'vitals'   => [
                    'Heart Rate'               => (float) $latest->heart_rate,
                    'Body Temperature'         => (float) $latest->body_temperature,
                    'Oxygen Saturation'        => (float) $latest->oxygen_saturation,
                    'Systolic Blood Pressure'  => (float) $latest->systolic_bp,
                    'Diastolic Blood Pressure' => (float) $latest->diastolic_bp,
                    'Age'                      => (int)   $latest->age,
                    'Gender'                   => $latest->gender,
                    'Derived_Pulse_Pressure'   => (float) ($latest->pulse_pressure ?? $pulsePressure),
                    'Derived_BMI'              => (float) ($latest->bmi ?? 0),
                    'Derived_MAP'              => (float) ($latest->map ?? $mapValue),
                ],
            ]);

            $reportPayload = $response->json();
            if (is_array($reportPayload)) {
                Cache::put($cacheKey, $reportPayload, now()->addSeconds(self::RECOMMENDATION_CACHE_TTL_SECONDS));
            }

            return response()->json([...$reportPayload, 'source' => 'fresh']);
        } catch (\Exception $e) {
            return response()->json(['error' => 'AI Service Unavailable: ' . $e->getMessage()], 503);
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Live Status
    // ──────────────────────────────────────────────────────────────────────────
    public function getLiveStatus(Request $request)
    {
        /** @var User|null $user */
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $sessionCacheKey = "health_session_live_user_{$user->id}";
        $sessionLive     = Cache::get($sessionCacheKey);

        $liveSampleKey = "health_live_sample_user_{$user->id}";
        $liveSample    = Cache::get($liveSampleKey);
        $cycleState    = $this->resolveCycleState((int) $user->id);

        $latest = HealthData::where('user_id', $user->id)
            ->latest('created_at')
            ->first();

        $modelPredictedRisk = null;
        if ($latest && is_array($latest->probabilities)) {
            $modelPredictedRisk = $this->inferModelRiskFromProbabilities($latest->probabilities);
        }

        if (!$latest && !$liveSample) {
            if (is_array($sessionLive)) {
                return response()->json([
                    'status' => 'success',
                    'data'   => [
                        'latest_vitals'      => $this->formatSessionVitals($sessionLive),
                        'risk'               => null,
                        'latest_recorded_at' => $sessionLive['captured_at'] ?? null,
                        'source'             => 'session_cache',
                        'phase'              => $sessionLive['state'] ?? 'WAITING_FOR_FINGER',
                        'remaining_seconds'  => 0,
                        'ui_message'         => $sessionLive['ui_message'] ?? 'Waiting for measurement.',
                        'progress'           => $sessionLive['progress'] ?? 0,
                    ],
                ]);
            }

            return response()->json([
                'status'  => 'success',
                'message' => 'No live data found yet',
                'data'    => [
                    'latest_vitals'      => null,
                    'risk'               => null,
                    'latest_recorded_at' => null,
                    ...$cycleState,
                ],
            ]);
        }

        if (is_array($sessionLive)) {
            $sessionRisk = is_array($sessionLive['risk'] ?? null)
                ? $sessionLive['risk']
                : null;
            $resolvedRisk = $sessionRisk ?? [
                'model_predicted_risk' => $modelPredictedRisk,
                'predicted_risk' => (string)($latest->predicted_risk ?? 'unknown'),
                'probabilities' => $latest->probabilities ?? [],
                'alert' => (bool)($latest->alert ?? false),
            ];

            return response()->json([
                'status' => 'success',
                'data'   => [
                    'latest_vitals'      => $this->formatSessionVitals($sessionLive),
                    'risk'               => $resolvedRisk,
                    'latest_recorded_at' => $sessionLive['captured_at'] ?? $latest?->created_at?->toIso8601String(),
                    'source'             => 'session_cache',
                    'phase'              => $sessionLive['state'] ?? 'WAITING_FOR_FINGER',
                    'remaining_seconds'  => 0,
                    'ui_message'         => $sessionLive['ui_message'] ?? 'Waiting for measurement.',
                    'progress'           => $sessionLive['progress'] ?? 0,
                ],
            ]);
        }

        if ($liveSample) {
            return response()->json([
                'status' => 'success',
                'data'   => [
                    'latest_vitals' => [
                        'heart_rate'   => (float) ($liveSample['heart_rate'] ?? 0),
                        'spo2'         => (float) ($liveSample['spo2'] ?? 0),
                        'systolic_bp'  => (float) ($liveSample['systolic_bp'] ?? 0),
                        'diastolic_bp' => (float) ($liveSample['diastolic_bp'] ?? 0),
                        'temperature'  => (float) ($liveSample['temperature'] ?? 0),
                    ],
                    'risk' => [
                        'model_predicted_risk' => $modelPredictedRisk,
                        'predicted_risk' => (string) ($latest->predicted_risk ?? 'unknown'),
                        'probabilities'  => $latest->probabilities ?? [],
                        'alert'          => (bool) ($latest->alert ?? false),
                    ],
                    'latest_recorded_at' => $liveSample['recorded_at'] ?? $latest?->created_at?->toIso8601String(),
                    'source'             => 'raw_live_sample',
                    ...$cycleState,
                ],
            ]);
        }

        return response()->json([
            'status' => 'success',
            'data'   => [
                'latest_vitals' => [
                    'heart_rate'   => (float) $latest->heart_rate,
                    'spo2'         => (float) $latest->oxygen_saturation,
                    'systolic_bp'  => (float) $latest->systolic_bp,
                    'diastolic_bp' => (float) $latest->diastolic_bp,
                    'temperature'  => (float) $latest->body_temperature,
                ],
                'risk' => [
                    'model_predicted_risk' => $modelPredictedRisk,
                    'predicted_risk' => (string) $latest->predicted_risk,
                    'probabilities'  => $latest->probabilities ?? [],
                    'alert'          => (bool) $latest->alert,
                ],
                'latest_recorded_at' => $latest->created_at?->toIso8601String(),
                'source'             => 'averaged_db',
                ...$cycleState,
            ],
        ]);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Metrics Overview
    // ──────────────────────────────────────────────────────────────────────────
    public function getMetricsOverview(Request $request)
    {
        /** @var User|null $user */
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $period = strtolower((string) $request->query('period', 'week'));
        $service = app(MetricsOverviewService::class);
        $data = $service->getOrCompute($user->id, $period);

        return response()->json([
            'status' => 'success',
            'period' => $period,
            'data'   => $data,
        ]);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Metrics History
    // ──────────────────────────────────────────────────────────────────────────
    public function getMetricsHistory(Request $request)
    {
        /** @var User|null $user */
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $period = strtolower((string) $request->query('period', 'week'));
        $days   = match ($period) {
            'day'   => 1,
            'month' => 30,
            'year'  => 365,
            default => 7,
        };

        $now   = now();
        $start = $now->copy()->subDays($days);

        $timeColumn = Schema::hasColumn('health_data', 'timestamp')
            ? 'timestamp'
            : 'created_at';

        $rows = HealthData::where('user_id', $user->id)
            ->whereBetween($timeColumn, [$start, $now])
            ->where(function ($query) {
                $query
                    ->where('heart_rate', '>', 0)
                    ->orWhere('oxygen_saturation', '>', 0)
                    ->orWhere('body_temperature', '>', 0)
                    ->orWhere('systolic_bp', '>', 0)
                    ->orWhere('diastolic_bp', '>', 0);
            })
            ->orderByDesc($timeColumn)
            ->get(['created_at', 'heart_rate', 'oxygen_saturation', 'body_temperature', 'systolic_bp', 'diastolic_bp']);

        $points = $rows->map(function ($row) {
            return [
                'timestamp'    => $row->created_at?->toIso8601String(),
                'heart_rate'   => (float) $row->heart_rate,
                'spo2'         => (float) $row->oxygen_saturation,
                'temperature'  => (float) $row->body_temperature,
                'systolic_bp'  => (float) $row->systolic_bp,
                'diastolic_bp' => (float) $row->diastolic_bp,
            ];
        })->values();

        return response()->json([
            'status' => 'success',
            'period' => $period,
            'data'   => [
                'chart_points' => $points,
                'total'        => $rows->count(),
                'range_start'  => $start->toIso8601String(),
                'range_end'    => $now->toIso8601String(),
            ],
        ]);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Profile Update
    // ──────────────────────────────────────────────────────────────────────────
    public function update(Request $request)
    {
        /** @var User|null $user */
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $validated = $request->validate([
            'first_name'   => 'sometimes|string|max:255',
            'last_name'    => 'sometimes|string|max:255',
            'dob'          => 'sometimes|date',
            'gender'       => 'sometimes|in:male,female,other',
            'weight'       => 'sometimes|numeric|min:1|max:500',
            'height'       => 'sometimes|numeric|min:1|max:300',
            'systolic_bp'  => 'sometimes|numeric|min:40|max:300',
            'diastolic_bp' => 'sometimes|numeric|min:30|max:250',
        ]);

        if (empty($validated)) {
            return response()->json(['message' => 'No valid profile fields provided', 'data' => $user]);
        }

        $user->fill($validated);
        $user->save();

        return response()->json(['message' => 'Profile updated successfully', 'data' => $user->fresh()]);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Private Helpers
    // ──────────────────────────────────────────────────────────────────────────
    private function formatSessionVitals(array $sessionLive): ?array
    {
        $vitals = $sessionLive['vitals'] ?? null;
        if (!is_array($vitals)) return null;

        return [
            'heart_rate'   => (float) ($vitals['heart_rate'] ?? 0),
            'spo2'         => (float) ($vitals['oxygen_saturation'] ?? 0),
            'systolic_bp'  => (float) ($vitals['systolic_bp'] ?? 0),
            'diastolic_bp' => (float) ($vitals['diastolic_bp'] ?? 0),
            'temperature'  => (float) ($vitals['body_temperature'] ?? 0),
        ];
    }

    private function resolveCycleState(int $userId): array
    {
        $now      = now();
        $cacheKey = "health_ingest_buffer_user_{$userId}";

        $buffer = Cache::get($cacheKey, [
            'phase'               => 'measuring',
            'window_started_at'   => $now->toIso8601String(),
            'cooldown_started_at' => null,
            'samples'             => [],
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
                    'phase'             => 'cooldown',
                    'remaining_seconds' => max(1, self::COOLDOWN_SECONDS - $cooldownElapsedSeconds),
                    'ui_message'        => 'Remove your hand. Wait 3 seconds, then place it again.',
                ];
            }

            return [
                'phase'             => 'measuring',
                'remaining_seconds' => self::AGG_WINDOW_SECONDS,
                'ui_message'        => 'Measuring... keep your hand steady.',
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

        $elapsedSeconds   = $windowStartedAt->diffInSeconds($now);
        $remainingSeconds = max(1, self::AGG_WINDOW_SECONDS - $elapsedSeconds);

        return [
            'phase'             => 'measuring',
            'remaining_seconds' => $remainingSeconds,
            'ui_message'        => 'Measuring... keep your hand steady.',
        ];
    }


    private function recommendationCacheKey(int $userId, int $healthDataId, string $language): string
    {
        return "health_recommendation:user:{$userId}:record:{$healthDataId}:lang:{$language}";
    }

    private function inferModelRiskFromProbabilities(array $probabilities): ?string
    {
        if (empty($probabilities)) {
            return null;
        }

        $highProb = $probabilities['High'] ?? $probabilities['high'] ?? null;
        if (is_numeric($highProb) && (float)$highProb >= self::MODEL_HIGH_RISK_THRESHOLD) {
            return 'High';
        }

        $bestLabel = null;
        $bestValue = -1.0;
        foreach ($probabilities as $label => $value) {
            if (!is_numeric($value)) {
                continue;
            }
            $score = (float)$value;
            if ($score > $bestValue) {
                $bestValue = $score;
                $bestLabel = (string)$label;
            }
        }

        return $bestLabel;
    }
}
