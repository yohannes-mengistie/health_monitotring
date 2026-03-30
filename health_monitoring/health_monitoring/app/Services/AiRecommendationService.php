<?php

namespace App\Services;

use Cloudstudio\Ollama\Facades\Ollama;
use Illuminate\Support\Facades\Log;

class AiRecommendationService
{
    protected string $model;

    public function __construct()
    {
        $this->model = config('ollama.model', 'koesn/llama3-openbiollm-8b');
    }

    /**
     * Get AI recommendation based on sensor data
     */
    public function getRecommendation(
        float $bpm,
        float $spo2,
        float $temperature,
        float $systolicBp,
        float $diastolicBp,
        ?string $userNote = null
    ): array {
        $prompt = $this->buildPrompt($bpm, $spo2, $temperature, $systolicBp, $diastolicBp, $userNote);

        try {
            $response = Ollama::prompt($prompt)
                ->model($this->model)
                ->options([
                    'temperature' => 0.3,      // Low for more consistent medical answers
                    'top_p'       => 0.9,
                    'max_tokens'  => 600,
                ])
                ->stream(false)
                ->ask();

            $aiResponse = trim($response);

            // Basic safety parsing
            return [
                'success'     => true,
                'recommendation' => $aiResponse,
                'model'       => $this->model,
            ];

        } catch (\Exception $e) {
            Log::error('Ollama AI Recommendation Error: ' . $e->getMessage());

            return [
                'success' => false,
                'error'   => 'Failed to get AI recommendation. Please try again later.',
                'recommendation' => 'Unable to analyze vitals at the moment.',
            ];
        }
    }

    /**
     * Build a safe, effective prompt for medical vitals
     */
    private function buildPrompt(
        float $bpm,
        float $spo2,
        float $temp,
        float $sbp,
        float $dbp,
        ?string $note
    ): string {
        $prompt = "You are a conservative and responsible medical AI assistant named OpenBioLLM.
You specialize in interpreting basic vital signs from wearable/home sensors.
You NEVER diagnose diseases. You ALWAYS recommend seeing a real doctor when needed.

Current vital signs:
- Heart Rate: {$bpm} BPM
- Oxygen Saturation (SpO2): {$spo2}%
- Body Temperature: {$temp}°C
- Blood Pressure: {$sbp}/{$dbp} mmHg";

        if ($note) {
            $prompt .= "\nAdditional note from user: {$note}";
        }

        $prompt .= "

Provide a short, clear, and safe response in maximum 4-5 sentences. Structure it as:
1. Overall assessment (normal / slightly elevated / concerning)
2. One or two gentle observations
3. Simple practical advice (if any)
4. Always end with this exact sentence: \"This is not a substitute for professional medical advice. Consult a doctor if you feel unwell or if readings remain abnormal.\"

Be empathetic, calm, and cautious. Do not alarm the user unnecessarily.";

        return $prompt;
    }
}
