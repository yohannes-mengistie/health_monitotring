<?php

namespace App\Services;

use Cloudstudio\Ollama\Facades\Ollama;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class AiRecommendationService
{
    protected string $model;
    /** @var string[] */
    protected array $fallbackModels;

    public function __construct()
    {
        $this->model = config('ollama-laravel.model', 'llama3.2:latest');
        $this->fallbackModels = [
            $this->model,
            'llama3.2:latest',
            'llama3.2',
            'llama3.1',
        ];
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
        ?string $userNote = null,
        ?string $currentFeeling = null,
        ?string $historySummary = null,
        ?array $structuredAssessment = null,
        string $language = 'english'
    ): array {
        $normalizedLanguage = str_starts_with(strtolower($language), 'am') ? 'amharic' : 'english';
        $prompt = $this->buildPrompt(
            $bpm,
            $spo2,
            $temperature,
            $systolicBp,
            $diastolicBp,
            $userNote,
            $currentFeeling,
            $historySummary,
            $structuredAssessment,
        );

        $attemptedModels = [];
        $lastError = null;

        foreach ($this->fallbackModels as $model) {
            if (in_array($model, $attemptedModels, true)) {
                continue;
            }

            $attemptedModels[] = $model;

            try {
                $response = Ollama::prompt($prompt)
                    ->model($model)
                    ->options([
                        'temperature' => 0.3,
                        'top_p'       => 0.9,
                        'num_predict' => 600,
                    ])
                    ->stream(false)
                    ->ask();

                $aiResponse = $this->extractRecommendationText($response);
                if ($aiResponse === '') {
                    throw new \RuntimeException('Ollama returned an empty recommendation.');
                }

                $translationError = null;
                if ($normalizedLanguage === 'amharic') {
                    $translated = $this->translateText($aiResponse, 'am');
                    if ($translated === null) {
                        $translationError = 'Translation failed or returned empty text.';
                    } else {
                        $aiResponse = $translated;
                    }
                }

                return [
                    'success' => true,
                    'recommendation' => $aiResponse,
                    'model' => $model,
                    'language' => $normalizedLanguage,
                    'translation_error' => $translationError,
                ];
            } catch (\Throwable $e) {
                $lastError = $e;
                Log::warning('Ollama AI model attempt failed', [
                    'model' => $model,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        Log::error('Ollama AI Recommendation Error: all model attempts failed', [
            'attempted_models' => $attemptedModels,
            'error' => $lastError?->getMessage(),
        ]);

        return [
            'success' => false,
            'error' => 'Failed to get AI recommendation. Check Ollama model availability and URL.',
            'recommendation' => 'Unable to analyze vitals at the moment.',
            'details' => $lastError?->getMessage(),
            'attempted_models' => $attemptedModels,
            'language' => $normalizedLanguage,
        ];
    }

    private function translateText(string $text, string $target): ?string
    {
        $config = config('services.translate', []);
        $url = $config['url'] ?? 'https://libretranslate.com/translate';
        $apiKey = $config['key'] ?? null;
        $timeout = (int) ($config['timeout'] ?? 12);

        try {
            $payload = [
                'q' => $text,
                'source' => 'en',
                'target' => $target,
                'format' => 'text',
            ];

            if (is_string($apiKey) && $apiKey !== '') {
                $payload['api_key'] = $apiKey;
            }

            $response = Http::timeout($timeout)->asForm()->post($url, $payload);
            if (!$response->ok()) {
                Log::warning('Translation service returned non-200 response', [
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
                return $this->translateViaMyMemory($text, $target) ?? null;
            }

            $data = $response->json();
            $translated = is_array($data) ? ($data['translatedText'] ?? null) : null;
            if (is_string($translated) && trim($translated) !== '') {
                return trim($translated);
            }
        } catch (\Throwable $e) {
            Log::warning('Translation request failed', [
                'error' => $e->getMessage(),
            ]);
        }
        return $this->translateViaMyMemory($text, $target) ?? null;
    }

    private function translateViaMyMemory(string $text, string $target): ?string
    {
        $timeout = (int) (config('services.translate.timeout', 12));
        $url = 'https://api.mymemory.translated.net/get';
        $chunks = $this->chunkParagraphs($text, 450);
        $translatedChunks = [];
        $separator = "\n\n";

        try {
            foreach ($chunks as $chunk) {
                $response = Http::timeout($timeout)->get($url, [
                    'q' => $chunk,
                    'langpair' => 'en|' . $target,
                ]);

                if (!$response->ok()) {
                    Log::warning('MyMemory translation returned non-200 response', [
                        'status' => $response->status(),
                        'body' => $response->body(),
                    ]);
                    return null;
                }

                $data = $response->json();
                $translated = is_array($data)
                    ? ($data['responseData']['translatedText'] ?? null)
                    : null;
                if (!is_string($translated) || trim($translated) === '') {
                    return null;
                }

                $translatedChunks[] = trim($translated);
            }

            if (!empty($translatedChunks)) {
                return implode($separator, $translatedChunks);
            }
        } catch (\Throwable $e) {
            Log::warning('MyMemory translation request failed', [
                'error' => $e->getMessage(),
            ]);
        }

        return null;
    }

    /**
     * Split text into chunks that stay under a safe character limit.
     * Uses whitespace boundaries to avoid breaking words.
     */
    private function chunkText(string $text, int $maxChars): array
    {
        $trimmed = trim($text);
        if ($trimmed === '') {
            return [];
        }

        if (strlen($trimmed) <= $maxChars) {
            return [$trimmed];
        }

        $words = preg_split('/\s+/', $trimmed) ?: [];
        $chunks = [];
        $current = '';

        foreach ($words as $word) {
            if ($word === '') {
                continue;
            }

            $candidate = $current === '' ? $word : $current . ' ' . $word;
            if (strlen($candidate) > $maxChars) {
                if ($current !== '') {
                    $chunks[] = $current;
                }
                $current = $word;
                continue;
            }

            $current = $candidate;
        }

        if ($current !== '') {
            $chunks[] = $current;
        }

        return $chunks;
    }

    /**
     * Split text by paragraphs first, then by word size if needed.
     */
    private function chunkParagraphs(string $text, int $maxChars): array
    {
        $normalized = trim($text);
        if ($normalized === '') {
            return [];
        }

        $paragraphs = preg_split("/\n{2,}/", $normalized) ?: [];
        $chunks = [];

        foreach ($paragraphs as $paragraph) {
            $paragraph = trim($paragraph);
            if ($paragraph === '') {
                continue;
            }

            if (strlen($paragraph) <= $maxChars) {
                $chunks[] = $paragraph;
                continue;
            }

            $chunks = array_merge($chunks, $this->chunkText($paragraph, $maxChars));
        }

        return $chunks;
    }

    private function extractRecommendationText(mixed $response): string
    {
        if (is_array($response)) {
            $value = $response['response'] ?? $response['message']['content'] ?? null;
            return is_string($value) ? trim($value) : '';
        }

        if (is_string($response)) {
            return trim($response);
        }

        return '';
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
        ?string $note,
        ?string $currentFeeling,
        ?string $historySummary,
        ?array $structuredAssessment
    ): string {
        $userFeelingContext = $currentFeeling
            ? "Current Feeling (user-described): {$currentFeeling}\n"
            : '';

        $historyContext = $historySummary
            ? "Recent Health History Summary: {$historySummary}\n"
            : '';

        $structuredContext = $this->formatStructuredAssessmentContext($structuredAssessment);

        return "### SYSTEM INSTRUCTIONS:
    You are a personal clinical assistant for the current user.
    Provide a concise, evidence-aligned vitals assessment similar to a modern triage summary.
    Use professional, supportive language and practical recommendations.
    Address the user directly as \"you\" and \"your\".
    Do not refer to the user as \"the patient\" or \"patients\".
Do not diagnose diseases.

### CONTEXT:
    Your Current Vitals:
- HR: {$bpm} BPM
- SpO2: {$spo2}%
- Temp: {$temp}°C
- BP: {$sbp}/{$dbp} mmHg
" . ($note ? "User Reported Symptoms: {$note}\n" : "")
            . $userFeelingContext
            . $structuredContext
            . $historyContext . "

### GUIDELINES:
1. Compare readings to standard adult reference ranges:
   - HR: 60-100 BPM
   - SpO2: 95-100%
   - Temp: 36.1-37.2°C
   - BP: <120/80 mmHg
2. Assess risk level (Low, Moderate, High) based on combined findings and potential short-term risk.
3. Use accurate medical terms when appropriate (e.g., Tachycardia, Bradycardia, Hypotension, Hypertension, Febrile).
4. Prioritize recommendations by urgency: immediate actions first, then lifestyle and monitoring steps.
5. Keep recommendations realistic for home monitoring.
6. Never output empty bullets. If something is not applicable, write one clear sentence instead.
7. Integrate the user's current feeling and recent history into prioritization without ignoring objective vitals.

### OUTPUT FORMAT:
[Clinical Assessment]
(2-4 sentences: summarize key findings, note deviations, and likely clinical significance.)

[Risk Stratification]
(Level: Low/Moderate/High. Include a one-sentence justification grounded in the vitals.)

[Clinical Recommendations]
(3-5 bullet points. Start with urgent steps if needed, then practical follow-up steps.)

[Feedback and Monitoring Plan]
(2-4 bullet points describing what to monitor in the next 24-72h, what trend changes matter, and when to escalate care.)";
    }

    private function formatStructuredAssessmentContext(?array $structuredAssessment): string
    {
        if (empty($structuredAssessment)) {
            return '';
        }

        $symptom = $structuredAssessment['symptom'] ?? [];
        $opqrst = $structuredAssessment['opqrst'] ?? [];
        $background = $structuredAssessment['background'] ?? [];
        $triage = $structuredAssessment['triage'] ?? [];

        $symptomLabel = is_array($symptom) ? ($symptom['label'] ?? null) : null;
        $severity = is_array($opqrst) ? ($opqrst['severity'] ?? null) : null;
        $onset = is_array($opqrst) ? ($opqrst['onset'] ?? null) : null;
        $quality = is_array($opqrst) ? ($opqrst['quality'] ?? null) : null;
        $timing = is_array($opqrst) ? ($opqrst['timing'] ?? null) : null;
        $redFlag = is_array($triage) ? ($triage['red_flag_yes'] ?? null) : null;
        $medication = is_array($background) ? ($background['medication_taken_today'] ?? null) : null;
        $conditions = is_array($background) ? ($background['known_conditions'] ?? []) : [];

        $conditionsText = is_array($conditions) && !empty($conditions)
            ? implode(', ', array_map(fn($c) => (string) $c, $conditions))
            : 'None reported';

        $lines = [
            'Structured Clinical Assessment (OPQRST):',
            '- Selected symptom: ' . (($symptomLabel === null || $symptomLabel === '') ? 'N/A' : (string) $symptomLabel),
            '- Onset: ' . (($onset === null || $onset === '') ? 'N/A' : (string) $onset),
            '- Quality: ' . (($quality === null || $quality === '') ? 'N/A' : (string) $quality),
            '- Severity: ' . (($severity === null || $severity === '') ? 'N/A' : ((string) $severity . '/10')),
            '- Timing: ' . (($timing === null || $timing === '') ? 'N/A' : (string) $timing),
            '- Red flag positive: ' . ($redFlag === null ? 'N/A' : ($redFlag ? 'Yes' : 'No')),
            '- Known conditions: ' . $conditionsText,
            '- Medication taken today: ' . (($medication === null || $medication === '') ? 'N/A' : (string) $medication),
        ];

        return implode("\n", $lines) . "\n";
    }
}
