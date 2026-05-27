<?php

namespace App\Services;

use App\Models\HealthData;
use Illuminate\Support\Facades\Cache;

class VitalsTrendService
{
    public function getSummaryForUser(int $userId): string
    {
        return Cache::remember("vitals_trend_{$userId}", now()->addMinutes(30), function () use ($userId) {
            return $this->computeSummary($userId);
        });
    }

    private function computeSummary(int $userId): string
    {
        $recent = HealthData::where('user_id', $userId)
            ->orderByDesc('created_at')
            ->limit(30)
            ->get([
                'heart_rate',
                'oxygen_saturation',
                'body_temperature',
                'systolic_bp',
                'diastolic_bp',
                'created_at',
            ]);

        if ($recent->isEmpty()) {
            return '';
        }

        $metrics = [
            'HR' => ['col' => 'heart_rate', 'unit' => 'BPM', 'low' => 60, 'high' => 100],
            'SpO2' => ['col' => 'oxygen_saturation', 'unit' => '%', 'low' => 95, 'high' => 100],
            'Temp' => ['col' => 'body_temperature', 'unit' => '°C', 'low' => 36.1, 'high' => 37.2],
            'SBP' => ['col' => 'systolic_bp', 'unit' => 'mmHg', 'low' => 90, 'high' => 120],
        ];

        $lines = [];
        foreach ($metrics as $label => $m) {
            $values = $recent->pluck($m['col'])->filter()->map(fn($v) => (float) $v);
            if ($values->isEmpty()) {
                continue;
            }
            $avg = round($values->avg(), 1);
            $latest = round($values->first(), 1);
            $delta = round($latest - $avg, 1);
            $trend = $delta > 0 ? "+{$delta}" : (string) $delta;
            $flag = ($latest < $m['low'] || $latest > $m['high']) ? ' ⚠' : '';
            $lines[] = "{$label}: avg {$avg}{$m['unit']}, latest {$latest}{$m['unit']} ({$trend}){$flag}";
        }

        $span = $recent->last()->created_at->diffForHumans($recent->first()->created_at, true);
        return "30-reading trend over {$span}: " . implode('; ', $lines);
    }

    public function invalidate(int $userId): void
    {
        Cache::forget("vitals_trend_{$userId}");
    }
}
