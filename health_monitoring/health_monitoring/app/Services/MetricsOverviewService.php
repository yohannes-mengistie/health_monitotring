<?php

namespace App\Services;

use App\Models\HealthData;
use App\Models\MetricsOverview;
use Illuminate\Support\Facades\Schema;

class MetricsOverviewService
{
    private const PERIOD_DAYS = [
        'day' => 1,
        'week' => 7,
        'month' => 30,
        'year' => 365,
    ];

    public function refreshForUser(int $userId): void
    {
        foreach (array_keys(self::PERIOD_DAYS) as $period) {
            $data = $this->computeForUser($userId, $period);
            $this->storeSnapshot($userId, $period, $data);
        }
    }

    public function getOrCompute(int $userId, string $period): array
    {
        $normalized = $this->normalizePeriod($period);
        $existing = MetricsOverview::where('user_id', $userId)
            ->where('period', $normalized)
            ->orderByDesc('computed_at')
            ->first();

        if ($existing) {
            return $existing->data ?? [];
        }

        $data = $this->computeForUser($userId, $normalized);
        $this->storeSnapshot($userId, $normalized, $data);

        return $data;
    }

    private function storeSnapshot(int $userId, string $period, array $data): void
    {
        MetricsOverview::updateOrCreate(
            ['user_id' => $userId, 'period' => $period],
            ['data' => $data, 'computed_at' => now()]
        );
    }

    private function computeForUser(int $userId, string $period): array
    {
        $period = $this->normalizePeriod($period);
        $days = self::PERIOD_DAYS[$period] ?? self::PERIOD_DAYS['week'];
        $now = now();
        $currentStart = $now->copy()->subDays($days);
        $previousStart = $currentStart->copy()->subDays($days);

        $timeColumn = Schema::hasColumn('health_data', 'timestamp')
            ? 'timestamp'
            : 'created_at';

        $baseQuery = HealthData::where('user_id', $userId);
        $latest = (clone $baseQuery)->orderByDesc($timeColumn)->first();

        if (!$latest) {
            return [
                'pinned_metrics' => [],
                'other_metrics' => [],
                'chart_points' => [],
                'health_score' => ['value' => 0, 'label' => 'No Data'],
                'insights' => [],
                'summary_statistics' => [],
                'range_coverage' => [],
            ];
        }

        $current = (clone $baseQuery)->whereBetween($timeColumn, [$currentStart, $now]);
        $previous = (clone $baseQuery)->whereBetween($timeColumn, [$previousStart, $currentStart]);

        $currentStats = [
            'avg_heart_rate' => (float) $current->avg('heart_rate'),
            'avg_spo2' => (float) $current->avg('oxygen_saturation'),
            'avg_temperature' => (float) $current->avg('body_temperature'),
            'avg_systolic' => (float) $current->avg('systolic_bp'),
            'avg_diastolic' => (float) $current->avg('diastolic_bp'),
        ];

        $previousStats = [
            'avg_heart_rate' => (float) $previous->avg('heart_rate'),
            'avg_spo2' => (float) $previous->avg('oxygen_saturation'),
            'avg_temperature' => (float) $previous->avg('body_temperature'),
            'avg_systolic' => (float) $previous->avg('systolic_bp'),
            'avg_diastolic' => (float) $previous->avg('diastolic_bp'),
        ];

        $trend = function (float $currentValue, float $previousValue): float {
            if ($previousValue == 0.0) return 0.0;
            return round((($currentValue - $previousValue) / $previousValue) * 100, 2);
        };

        $currentRows = (clone $baseQuery)
            ->whereBetween($timeColumn, [$currentStart, $now])
            ->orderBy($timeColumn)
            ->get([
                'created_at',
                'heart_rate',
                'oxygen_saturation',
                'body_temperature',
                'systolic_bp',
                'diastolic_bp',
            ]);

        $chartPoints = $currentRows->map(function ($row) {
            return [
                'timestamp' => $row->created_at?->toIso8601String(),
                'heart_rate' => (float) $row->heart_rate,
                'spo2' => (float) $row->oxygen_saturation,
                'temperature' => (float) $row->body_temperature,
                'systolic_bp' => (float) $row->systolic_bp,
                'diastolic_bp' => (float) $row->diastolic_bp,
            ];
        })->values()->all();

        $heartRateValues = $currentRows->pluck('heart_rate')->map(fn($v) => (float) $v)->values()->all();
        $spo2Values = $currentRows->pluck('oxygen_saturation')->map(fn($v) => (float) $v)->values()->all();
        $temperatureValues = $currentRows->pluck('body_temperature')->map(fn($v) => (float) $v)->values()->all();
        $systolicValues = $currentRows->pluck('systolic_bp')->map(fn($v) => (float) $v)->values()->all();
        $diastolicValues = $currentRows->pluck('diastolic_bp')->map(fn($v) => (float) $v)->values()->all();

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

        $healthScoreValue = $this->calculateHealthScore($summaryStatistics, (string) $latest->predicted_risk);
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

        return [
            'health_score' => ['value' => $healthScoreValue, 'label' => $healthScoreLabel],
            'insights' => $insights,
            'pinned_metrics' => [
                [
                    'key' => 'heart_rate',
                    'label' => 'Average Heart Rate',
                    'value' => round($currentStats['avg_heart_rate'] ?: (float) $latest->heart_rate, 2),
                    'unit' => 'bpm',
                    'trend_percent' => $trend($currentStats['avg_heart_rate'], $previousStats['avg_heart_rate']),
                    'previous_value' => round($previousStats['avg_heart_rate'], 2),
                ],
                [
                    'key' => 'spo2',
                    'label' => 'Average SpO2',
                    'value' => round($currentStats['avg_spo2'] ?: (float) $latest->oxygen_saturation, 2),
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
                        'systolic' => (int) round($latest->systolic_bp),
                        'diastolic' => (int) round($latest->diastolic_bp),
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
                    'value' => round((float) $latest->body_temperature, 2),
                    'unit' => 'C',
                    'trend_percent' => $trend($currentStats['avg_temperature'], $previousStats['avg_temperature']),
                    'previous_value' => round($previousStats['avg_temperature'], 2),
                ],
            ],
            'chart_points' => $chartPoints,
            'summary_statistics' => $summaryStatistics,
            'range_coverage' => $rangeCoverage,
            'comparison' => ['current' => $currentStats, 'previous' => $previousStats],
            'latest_vitals' => [
                'heart_rate' => (float) $latest->heart_rate,
                'spo2' => (float) $latest->oxygen_saturation,
                'systolic_bp' => (float) $latest->systolic_bp,
                'diastolic_bp' => (float) $latest->diastolic_bp,
                'temperature' => (float) $latest->body_temperature,
            ],
            'risk' => [
                'predicted_risk' => (string) $latest->predicted_risk,
                'probabilities' => $latest->probabilities ?? [],
                'alert' => (bool) $latest->alert,
            ],
            'latest_recorded_at' => $latest->created_at?->toIso8601String(),
        ];
    }

    private function normalizePeriod(string $period): string
    {
        $period = strtolower(trim($period));
        return array_key_exists($period, self::PERIOD_DAYS) ? $period : 'week';
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
            $variance += pow(((float) $value - $avg), 2);
        }

        return [
            'avg' => round($avg, 2),
            'min' => round(min($values), 2),
            'max' => round(max($values), 2),
            'std_dev' => round(sqrt($variance / $count), 2),
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
            $f = (float) $value;
            if ($f >= $min && $f <= $max) {
                $inRange++;
            }
        }

        return round(($inRange / count($values)) * 100, 2);
    }

    private function calculateHealthScore(array $stats, string $riskLabel): int
    {
        $score = 100.0;
        $avgHr = (float) ($stats['heart_rate']['avg'] ?? 0.0);
        $avgSpo2 = (float) ($stats['spo2']['avg'] ?? 0.0);
        $avgTemp = (float) ($stats['temperature']['avg'] ?? 0.0);
        $avgSys = (float) ($stats['systolic_bp']['avg'] ?? 0.0);
        $avgDia = (float) ($stats['diastolic_bp']['avg'] ?? 0.0);

        if ($avgSpo2 > 0 && $avgSpo2 < 95) $score -= (95 - $avgSpo2) * 3.5;
        if ($avgHr > 0 && ($avgHr < 60 || $avgHr > 100)) $score -= abs($avgHr - ($avgHr < 60 ? 60 : 100)) * 0.9;
        if ($avgTemp > 0 && ($avgTemp < 36.1 || $avgTemp > 37.5)) $score -= abs($avgTemp - ($avgTemp < 36.1 ? 36.1 : 37.5)) * 18;
        if ($avgSys > 130) $score -= ($avgSys - 130) * 0.45;
        if ($avgDia > 85) $score -= ($avgDia - 85) * 0.6;

        $risk = strtolower(trim($riskLabel));
        if ($risk === 'high') $score -= 20;
        elseif ($risk === 'medium') $score -= 10;

        return (int) max(0, min(100, round($score)));
    }

    private function buildInsights(
        array $summaryStatistics,
        array $rangeCoverage,
        string $period,
        array $currentStats,
        array $previousStats
    ): array {
        $periodLabel = ucfirst($period);
        $bestSpo2 = (float) ($summaryStatistics['spo2']['max'] ?? 0.0);
        $avgHr = (float) ($summaryStatistics['heart_rate']['avg'] ?? 0.0);
        $hrStdDev = (float) ($summaryStatistics['heart_rate']['std_dev'] ?? 0.0);
        $normalRange = round((
            (float) ($rangeCoverage['heart_rate'] ?? 0.0) +
            (float) ($rangeCoverage['spo2'] ?? 0.0) +
            (float) ($rangeCoverage['temperature'] ?? 0.0) +
            (float) ($rangeCoverage['systolic_bp'] ?? 0.0) +
            (float) ($rangeCoverage['diastolic_bp'] ?? 0.0)
        ) / 5, 2);

        $hrTrend = 0.0;
        if ((float) $previousStats['avg_heart_rate'] !== 0.0) {
            $hrTrend = round((((float) $currentStats['avg_heart_rate'] - (float) $previousStats['avg_heart_rate']) / (float) $previousStats['avg_heart_rate']) * 100, 2);
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
}
