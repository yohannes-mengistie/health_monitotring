<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Models\ClinicalAssessment;
use App\Models\HealthData;
use App\Models\RecommendationFeedback;
use App\Services\AiRecommendationService;
use App\Services\VitalsTrendService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Validator;

class AiRecommendationController extends Controller
{
    protected $aiService;
    protected $trendsService;

    public function __construct(
        AiRecommendationService $aiService,
        VitalsTrendService $trendsService
    ) {
        $this->aiService = $aiService;
        $this->trendsService = $trendsService;
    }

    public function analyze(Request $request)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json([
                'success' => false,
                'error' => 'Unauthenticated',
            ], 401);
        }

        $validator = Validator::make($request->all(), [
            'bpm'          => 'required|numeric|min:30|max:220',
            'spo2'         => 'required|numeric|min:70|max:100',
            'temperature'  => 'required|numeric|min:30|max:45',
            'systolic_bp'  => 'required|integer|min:70|max:220',
            'diastolic_bp' => 'required|integer|min:40|max:130',
            'language' => 'nullable|string|max:20',
            'user_note'    => 'nullable|string|max:600',
            'current_feeling' => 'nullable|string|max:400',
            'history_summary' => 'nullable|string|max:1200',
            'structured_assessment' => 'nullable|array',
            'structured_assessment.symptom' => 'nullable|array',
            'structured_assessment.opqrst' => 'nullable|array',
            'structured_assessment.background' => 'nullable|array',
            'structured_assessment.triage' => 'nullable|array',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'errors'  => $validator->errors()
            ], 422);
        }

        $structuredAssessment = $request->input('structured_assessment');
        $languageInput = $request->input('language', $request->input('lang', 'english'));
        $languageRaw = is_string($languageInput) ? $languageInput : 'english';
        $language = str_starts_with(strtolower($languageRaw), 'am') ? 'amharic' : 'english';

        $recentFeedback = RecommendationFeedback::where('user_id', $user->id)
            ->latest()
            ->limit(3)
            ->with('clinicalAssessment:id,symptom_label,risk_level')
            ->get()
            ->map(fn($f) => "{$f->action} on {$f->clinicalAssessment?->symptom_label} ({$f->clinicalAssessment?->risk_level} risk)")
            ->implode('; ');

        $result = $this->aiService->getRecommendation(
            bpm: $request->bpm,
            spo2: $request->spo2,
            temperature: $request->temperature,
            systolicBp: $request->systolic_bp,
            diastolicBp: $request->diastolic_bp,
            userNote: $request->user_note,
            currentFeeling: $request->input('current_feeling'),
            historySummary: $this->trendsService->getSummaryForUser($user->id),
            structuredAssessment: is_array($structuredAssessment)
                ? $structuredAssessment
                : null,
            language: $language,
            feedbackContext: $recentFeedback ?: null,
        );

        $this->storeClinicalAssessment(
            userId: $user->id,
            sourceEndpoint: 'POST /api/health/analysis-v2',
            structuredAssessment: is_array($structuredAssessment)
                ? $structuredAssessment
                : null,
            aiResult: $result,
            vitals: $validator->validated(),
        );

        return response()->json($result);
    }

    public function analyzeLatest(Request $request)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json([
                'success' => false,
                'error' => 'Unauthenticated',
            ], 401);
        }

        $latest = HealthData::where('user_id', $user->id)->latest()->first();
        if (!$latest) {
            return response()->json([
                'success' => false,
                'error' => 'No health data found for this user.',
            ], 404);
        }

        $languageInput = $request->input('language', $request->input('lang', 'english'));
        $languageRaw = is_string($languageInput) ? $languageInput : 'english';
        $language = str_starts_with(strtolower($languageRaw), 'am') ? 'amharic' : 'english';

        $result = $this->aiService->getRecommendation(
            bpm: (float)$latest->heart_rate,
            spo2: (float)$latest->oxygen_saturation,
            temperature: (float)$latest->body_temperature,
            systolicBp: (float)$latest->systolic_bp,
            diastolicBp: (float)$latest->diastolic_bp,
            userNote: $request->input('user_note'),
            currentFeeling: $request->input('current_feeling'),
            historySummary: $this->trendsService->getSummaryForUser($user->id),
            structuredAssessment: is_array($request->input('structured_assessment'))
                ? $request->input('structured_assessment')
                : null,
            language: $language,
        );

        $this->storeClinicalAssessment(
            userId: $user->id,
            sourceEndpoint: 'GET /api/health/analysis-v2',
            structuredAssessment: is_array($request->input('structured_assessment'))
                ? $request->input('structured_assessment')
                : null,
            aiResult: $result,
        );

        return response()->json([
            ...$result,
            'source' => 'ai_recommendation_v2',
        ]);
    }

    public function history(Request $request)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['success' => false, 'error' => 'Unauthenticated'], 401);
        }

        $validator = Validator::make($request->all(), [
            'limit' => 'nullable|integer|min:1|max:50',
            'offset' => 'nullable|integer|min:0',
            'from_date' => 'nullable|date',
            'to_date' => 'nullable|date|after_or_equal:from_date',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $query = ClinicalAssessment::where('user_id', $user->id)
            ->orderByDesc('created_at');

        if ($request->filled('from_date')) {
            $query->whereDate('created_at', '>=', $request->from_date);
        }
        if ($request->filled('to_date')) {
            $query->whereDate('created_at', '<=', $request->to_date);
        }

        $limit = (int) $request->input('limit', 10);
        $offset = (int) $request->input('offset', 0);

        $total = $query->count();
        $items = $query->skip($offset)->take($limit)->get([
            'id',
            'symptom_label',
            'severity',
            'high_risk',
            'risk_level',
            'ai_success',
            'ai_model',
            'recommendation_excerpt',
            'structured_response',
            'known_conditions',
            'medication_taken_today',
            'created_at',
        ]);

        return response()->json([
            'success' => true,
            'total' => $total,
            'limit' => $limit,
            'offset' => $offset,
            'items' => $items,
        ]);
    }

    public function show(int $id)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['success' => false, 'error' => 'Unauthenticated'], 401);
        }
        $record = ClinicalAssessment::where('id', $id)
            ->where('user_id', $user->id)
            ->first();
        if (!$record) {
            return response()->json(['success' => false, 'error' => 'Not found'], 404);
        }
        return response()->json(['success' => true, 'item' => $record]);
    }

    public function feedback(Request $request, int $id)
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['success' => false, 'error' => 'Unauthenticated'], 401);
        }

        $validator = Validator::make($request->all(), [
            'action' => 'required|in:viewed,dismissed,followed,shared',
            'note' => 'nullable|string|max:500',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $record = ClinicalAssessment::where('id', $id)
            ->where('user_id', $user->id)
            ->first();

        if (!$record) {
            return response()->json(['success' => false, 'error' => 'Recommendation not found'], 404);
        }

        $fb = RecommendationFeedback::create([
            'clinical_assessment_id' => $id,
            'user_id' => $user->id,
            'action' => $request->action,
            'note' => $request->note,
        ]);

        return response()->json(['success' => true, 'feedback_id' => $fb->id]);
    }

    private function storeClinicalAssessment(
        int $userId,
        string $sourceEndpoint,
        ?array $structuredAssessment,
        array $aiResult,
        array $vitals = []
    ): void {
        if (empty($structuredAssessment)) {
            return;
        }

        try {
            $symptom = $structuredAssessment['symptom'] ?? [];
            $opqrst = $structuredAssessment['opqrst'] ?? [];
            $background = $structuredAssessment['background'] ?? [];
            $triage = $structuredAssessment['triage'] ?? [];

            $symptomKey = is_array($symptom)
                ? (($symptom['key'] ?? null) !== null ? (string) $symptom['key'] : null)
                : null;
            $symptomLabel = is_array($symptom)
                ? (($symptom['label'] ?? null) !== null ? (string) $symptom['label'] : null)
                : null;

            $severityValue = is_array($opqrst) ? ($opqrst['severity'] ?? null) : null;
            $severity = is_numeric($severityValue) ? (int) $severityValue : null;
            if ($severity !== null) {
                $severity = max(1, min(10, $severity));
            }

            $highRiskRaw = is_array($symptom) ? ($symptom['high_risk'] ?? false) : false;
            $highRisk = filter_var($highRiskRaw, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE) ?? false;

            $redFlagRaw = is_array($triage) ? ($triage['red_flag_yes'] ?? null) : null;
            $redFlagYes = $redFlagRaw === null
                ? null
                : (filter_var($redFlagRaw, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE) ?? null);

            $knownConditions = is_array($background)
                ? (($background['known_conditions'] ?? null) ?: [])
                : [];
            if (!is_array($knownConditions)) {
                $knownConditions = [];
            }

            $medicationTakenToday = is_array($background)
                ? (($background['medication_taken_today'] ?? null) !== null
                    ? (string) $background['medication_taken_today']
                    : null)
                : null;

            $recommendation = $aiResult['recommendation'] ?? null;
            $excerpt = is_string($recommendation) ? trim($recommendation) : null;
            if ($excerpt !== null && strlen($excerpt) > 1500) {
                $excerpt = substr($excerpt, 0, 1500);
            }

            ClinicalAssessment::create([
                'user_id' => $userId,
                'source_endpoint' => $sourceEndpoint,
                'symptom_key' => $symptomKey,
                'symptom_label' => $symptomLabel,
                'severity' => $severity,
                'high_risk' => $highRisk,
                'red_flag_yes' => $redFlagYes,
                'medication_taken_today' => $medicationTakenToday,
                'known_conditions' => $knownConditions,
                'opqrst' => is_array($opqrst) ? $opqrst : [],
                'structured_assessment' => $structuredAssessment,
                'ai_success' => (bool) ($aiResult['success'] ?? false),
                'ai_model' => isset($aiResult['model']) ? (string) $aiResult['model'] : null,
                'predicted_risk' => isset($aiResult['predicted_risk'])
                    ? (string) $aiResult['predicted_risk']
                    : null,
                'risk_level' => $aiResult['structured']['risk_level'] ?? null,
                'structured_response' => $aiResult['structured'] ?? null,
                'language' => $aiResult['language'] ?? 'english',
                'requires_review' => in_array(
                    $aiResult['structured']['risk_level'] ?? '',
                    ['high', 'critical'],
                    true
                ),
                'vitals_snapshot' => [
                    'bpm' => $vitals['bpm'] ?? null,
                    'spo2' => $vitals['spo2'] ?? null,
                    'temperature' => $vitals['temperature'] ?? null,
                    'systolic_bp' => $vitals['systolic_bp'] ?? null,
                    'diastolic_bp' => $vitals['diastolic_bp'] ?? null,
                ],
                'recommendation_excerpt' => $excerpt,
            ]);
        } catch (\Throwable $e) {
            Log::warning('Failed to persist structured clinical assessment', [
                'user_id' => $userId,
                'source_endpoint' => $sourceEndpoint,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
