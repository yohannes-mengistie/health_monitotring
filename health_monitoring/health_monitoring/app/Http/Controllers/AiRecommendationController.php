<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Models\HealthData;
use App\Services\AiRecommendationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Validator;

class AiRecommendationController extends Controller
{
    protected $aiService;

    public function __construct(AiRecommendationService $aiService)
    {
        $this->aiService = $aiService;
    }

    public function analyze(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'bpm'          => 'required|numeric|min:30|max:220',
            'spo2'         => 'required|numeric|min:70|max:100',
            'temperature'  => 'required|numeric|min:30|max:45',
            'systolic_bp'  => 'required|integer|min:70|max:220',
            'diastolic_bp' => 'required|integer|min:40|max:130',
            'user_note'    => 'nullable|string|max:300',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'errors'  => $validator->errors()
            ], 422);
        }

        $result = $this->aiService->getRecommendation(
            bpm: $request->bpm,
            spo2: $request->spo2,
            temperature: $request->temperature,
            systolicBp: $request->systolic_bp,
            diastolicBp: $request->diastolic_bp,
            userNote: $request->user_note
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

        $result = $this->aiService->getRecommendation(
            bpm: (float)$latest->heart_rate,
            spo2: (float)$latest->oxygen_saturation,
            temperature: (float)$latest->body_temperature,
            systolicBp: (float)$latest->systolic_bp,
            diastolicBp: (float)$latest->diastolic_bp,
            userNote: $request->input('user_note')
        );

        return response()->json([
            ...$result,
            'source' => 'ai_recommendation_v2',
        ]);
    }
}
