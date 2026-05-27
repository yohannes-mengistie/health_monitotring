<?php

namespace App\Http\Controllers;

use App\Models\DeviceState;
use App\Models\HealthData;
use App\Models\MeasurementEvent;
use App\Models\MeasurementSession;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

class MeasurementSessionController extends Controller
{
    private const LIVE_CACHE_TTL_SECONDS = 120;
    private const RECOMMENDATION_CACHE_TTL_SECONDS = 1800;
    private const MODEL_HIGH_RISK_THRESHOLD = 0.3;

    public function ingestEvent(Request $request)
    {
        /** @var User|null $user */
        $user = Auth::user();
        if (!$user) {
            return response()->json(['error' => 'Unauthenticated'], 401);
        }

        $validated = $request->validate([
            'type' => 'required|string|in:status,progress,live,result,error,heartbeat',
            'session_id' => 'required|string|max:64',
            'device_id' => 'required|string|max:64',
            'captured_at' => 'nullable',
            'state' => 'nullable|string|max:40',
            'progress' => 'nullable|integer|min:0|max:100',
            'error_code' => 'nullable|string|max:80',
            'vitals' => 'nullable|array',
            'vitals.heart_rate' => 'nullable|numeric',
            'vitals.oxygen_saturation' => 'nullable|numeric',
            'vitals.body_temperature' => 'nullable|numeric',
            'vitals.systolic_bp' => 'nullable|numeric',
            'vitals.diastolic_bp' => 'nullable|numeric',
            'raw' => 'nullable|string',
        ]);

        $sessionId = $validated['session_id'];
        $deviceId = $validated['device_id'];
        $type = strtolower($validated['type']);
        $capturedAt = $this->resolveCapturedAt($validated['captured_at'] ?? null);

        $session = MeasurementSession::where('session_id', $sessionId)->first();
        if ($session && (int)$session->user_id !== (int)$user->id) {
            return response()->json(['error' => 'Session ownership mismatch'], 409);
        }

        if (!$session) {
            $session = MeasurementSession::create([
                'session_id' => $sessionId,
                'user_id' => $user->id,
                'device_id' => $deviceId,
                'state' => 'WAITING_FOR_FINGER',
                'started_at' => $capturedAt,
                'last_seen_at' => $capturedAt,
            ]);
        }

        $eventPayload = [
            'type' => $type,
            'session_id' => $sessionId,
            'device_id' => $deviceId,
            'captured_at' => $capturedAt?->toIso8601String(),
            'payload' => $validated,
        ];

        MeasurementEvent::create([
            'session_id' => $sessionId,
            'user_id' => $user->id,
            'device_id' => $deviceId,
            'type' => $type,
            'payload' => $validated,
            'captured_at' => $capturedAt,
        ]);

        $session->last_seen_at = $capturedAt;

        if ($type === 'status') {
            $state = strtoupper((string)($validated['state'] ?? 'WAITING_FOR_FINGER'));
            $session->state = $state;
        } elseif ($type === 'progress') {
            $session->last_progress = (int)($validated['progress'] ?? 0);
        } elseif ($type === 'live') {
            $session->last_live = $validated['vitals'] ?? null;
        } elseif ($type === 'result') {
            $session->last_result = $validated['vitals'] ?? null;
            $session->state = 'COMPLETE';
            $session->completed_at = $capturedAt;
        } elseif ($type === 'error') {
            $session->state = 'ERROR';
            $session->last_error_code = $validated['error_code'] ?? null;
        }

        $session->save();

        DeviceState::updateOrCreate(
            ['device_id' => $deviceId],
            [
                'user_id' => $user->id,
                'last_session_id' => $sessionId,
                'state' => $session->state,
                'last_seen_at' => $capturedAt,
                'last_error_code' => $session->last_error_code,
                'last_payload' => $eventPayload,
            ]
        );

        $this->cacheLiveState($user->id, $session, $validated, $capturedAt);

        if ($type === 'result') {
            $this->persistFinalResult($user, $validated['vitals'] ?? [], $deviceId);
        }

        return response()->json(['status' => 'success']);
    }

    private function resolveCapturedAt($raw): Carbon
    {
        if (is_numeric($raw)) {
            $timestamp = (float)$raw;
            if ($timestamp > 1000000000000) {
                $timestamp = $timestamp / 1000;
            }
            return Carbon::createFromTimestamp($timestamp);
        }

        if (is_string($raw)) {
            $parsed = Carbon::parse($raw, 'UTC');
            return $parsed instanceof Carbon ? $parsed : now();
        }

        return now();
    }

    private function cacheLiveState(int $userId, MeasurementSession $session, array $payload, Carbon $capturedAt): void
    {
        $state = $session->state ?? 'WAITING_FOR_FINGER';
        $cacheKey = "health_session_live_user_{$userId}";
        $previous = Cache::get($cacheKey, []);

        $incomingVitals = $payload['vitals'] ?? null;
        if (!is_array($incomingVitals) || empty($incomingVitals)) {
            $incomingVitals = $session->last_result ?? $session->last_live ?? null;
        }

        $vitals = $incomingVitals ?: ($previous['vitals'] ?? []);
        $progress = $payload['progress'] ?? $session->last_progress ?? ($previous['progress'] ?? 0);

        $cached = [
            'session_id' => $session->session_id,
            'device_id' => $session->device_id,
            'state' => $state,
            'progress' => (int)$progress,
            'vitals' => $vitals,
            'error_code' => $session->last_error_code,
            'captured_at' => $capturedAt->toIso8601String(),
            'ui_message' => $this->stateMessage($state, $session->last_error_code),
        ];

        Cache::put($cacheKey, $cached, now()->addSeconds(self::LIVE_CACHE_TTL_SECONDS));
    }

    private function stateMessage(string $state, ?string $errorCode): string
    {
        return match ($state) {
            'WAITING_FOR_FINGER' => 'Place your finger on the sensor to start.',
            'FINGER_DETECTED' => 'Finger detected. Hold still.',
            'STABILIZING' => 'Stabilizing signal. Keep steady.',
            'MEASURING' => 'Measuring... keep your hand steady.',
            'COMPLETE' => 'Measurement complete.',
            'REMOVE_FINGER' => 'Remove your finger from the sensor.',
            'ERROR' => $this->errorMessage($errorCode),
            default => 'Ready for measurement.',
        };
    }

    private function errorMessage(?string $errorCode): string
    {
        $normalized = strtoupper((string)$errorCode);
        return match ($normalized) {
            'FINGER_REMOVED_TOO_EARLY' => 'Finger removed too early. Please try again.',
            'MAX30100_INIT_FAILED' => 'Sensor initialization failed. Check the device.',
            default => 'Device error detected. Please retry.',
        };
    }

    private function persistFinalResult(User $user, array $vitals, string $deviceId): void
    {
        if (empty($vitals)) {
            return;
        }

        $systolicBp = (float)($vitals['systolic_bp'] ?? $user->systolic_bp ?? 0);
        $diastolicBp = (float)($vitals['diastolic_bp'] ?? $user->diastolic_bp ?? 0);

        $heightMeters = $this->normalizeHeightToMeters((float)$user->height);
        $genderCode = strtoupper(substr($user->gender ?? 'M', 0, 1));
        $useTimestamp = Schema::hasColumn('health_data', 'timestamp');
        $mlPayload = [
            'heart_rate' => (float)($vitals['heart_rate'] ?? 0),
            'spo2' => (float)($vitals['oxygen_saturation'] ?? 0),
            'temperature' => (float)($vitals['body_temperature'] ?? 0),
            'systolic_bp' => $systolicBp,
            'diastolic_bp' => $diastolicBp,
            'age' => (int)(date('Y') - date('Y', strtotime($user->dob))),
            'gender' => $genderCode,
            'patient_id' => (int)$user->id,
        ];

        try {
            $response = Http::timeout(3)->post('http://127.0.0.1:5000/predict', $mlPayload);
            if ($response->failed()) {
                throw new \Exception('ML Service returned an error');
            }

            $mlResult = $response->json();

            $pulsePressure = round($systolicBp - $diastolicBp, 2);
            $mapValue = round($diastolicBp + ($pulsePressure / 3), 2);
            $bmi = $user->weight && $heightMeters > 0
                ? round($user->weight / ($heightMeters * $heightMeters), 2)
                : null;

            $finalRisk = (string)($mlResult['predicted_risk'] ?? 'unknown');

            $probabilities = is_array($mlResult['probabilities'] ?? null)
                ? $mlResult['probabilities']
                : [];
            $modelRisk = $this->inferModelRiskFromProbabilities($probabilities)
                ?? ($mlResult['predicted_risk'] ?? null);

            $healthDataPayload = [
                'heart_rate' => (float)($vitals['heart_rate'] ?? 0),
                'body_temperature' => (float)($vitals['body_temperature'] ?? 0),
                'oxygen_saturation' => (float)($vitals['oxygen_saturation'] ?? 0),
                'systolic_bp' => $systolicBp,
                'diastolic_bp' => $diastolicBp,
                'age' => (int)(date('Y') - date('Y', strtotime($user->dob))),
                'weight_kg' => (float)($user->weight ?? 0),
                'height_m' => $heightMeters,
                'gender' => $user->gender ?? 'M',
                'user_id' => (int)$user->id,
                'bmi' => $bmi ?? 0,
                'pulse_pressure' => $pulsePressure,
                'map' => $mapValue,
                'device_id' => $deviceId,
                'predicted_risk' => $finalRisk,
                'probabilities' => $probabilities,
                'alert' => $finalRisk === 'High',
            ];

            if ($useTimestamp) {
                $healthDataPayload['timestamp'] = now();
            }

            $healthData = HealthData::create($healthDataPayload);

            $cacheKey = "health_session_live_user_{$user->id}";
            $cached = Cache::get($cacheKey, []);
            if (is_array($cached)) {
                $cached['risk'] = [
                    'model_predicted_risk' => $modelRisk,
                    'predicted_risk' => $finalRisk,
                    'probabilities' => $probabilities,
                    'alert' => $finalRisk === 'High',
                ];
                Cache::put($cacheKey, $cached, now()->addSeconds(self::LIVE_CACHE_TTL_SECONDS));
            }

            Log::info('Final result saved', ['healthData_id' => $healthData->id]);
        } catch (\Throwable $e) {
            Log::error('ML service error for result', [
                'error' => $e->getMessage(),
                'payload' => $mlPayload,
            ]);
        }
    }

    private function applyWhoSafetyLayer(
        string $modelRisk,
        array $vitals,
        float $systolicBp,
        float $diastolicBp,
        float $mapValue
    ): string {
        $heartRate = (float)($vitals['heart_rate'] ?? 0);
        $temperature = (float)($vitals['body_temperature'] ?? 0);
        $spo2 = (float)($vitals['oxygen_saturation'] ?? 0);

        $redFlags = (
            $spo2 < 92 ||
            $systolicBp < 90 ||
            $mapValue < 65 ||
            $temperature >= 38.5 ||
            $temperature <= 35.0 ||
            $heartRate < 45 ||
            $heartRate > 120
        );

        $stable = (
            $spo2 >= 95 &&
            $heartRate >= 60 && $heartRate <= 100 &&
            $systolicBp >= 100 && $systolicBp <= 140 &&
            $diastolicBp >= 60 && $diastolicBp <= 90 &&
            $temperature >= 36.0 && $temperature <= 37.5 &&
            $mapValue >= 70
        );

        if (strtolower($modelRisk) === 'high' && $stable && !$redFlags) {
            return 'Medium';
        }

        return $modelRisk;
    }

    private function normalizeHeightToMeters(float $rawHeight): float
    {
        if ($rawHeight <= 0) {
            return 0.0;
        }

        if ($rawHeight > 3) {
            return round($rawHeight / 100, 2);
        }

        return round($rawHeight, 2);
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
