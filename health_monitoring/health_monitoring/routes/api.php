<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\SensorController;
use App\Http\Controllers\AiRecommendationController;
use App\Http\Controllers\MeasurementSessionController;
use App\Http\Controllers\Auth\RegisterController;
use App\Http\Controllers\Auth\LoginController;

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/health-data', [SensorController::class, 'ingest']);
    Route::post('/measurement-events', [MeasurementSessionController::class, 'ingestEvent']);
    Route::get('/user', [RegisterController::class, 'index']);
    Route::get('/health/analysis', [SensorController::class, 'getDetailedAnalysis']);
    Route::get('/health/analysis-v2', [AiRecommendationController::class, 'analyzeLatest']);
    Route::get('/health/recommendations/history', [AiRecommendationController::class, 'history']);
    Route::get('/health/recommendations/{id}', [AiRecommendationController::class, 'show']);
    Route::get('/health/live-status', [SensorController::class, 'getLiveStatus']);
    Route::get('/health/metrics-overview', [SensorController::class, 'getMetricsOverview']);
    Route::get('/health/metrics-history', [SensorController::class, 'getMetricsHistory']);
    Route::patch('/update', [SensorController::class, 'update']);
});

Route::post('/register', [RegisterController::class, 'store']);
Route::post('/login', [LoginController::class, 'login']);

Route::middleware(['auth:sanctum', 'throttle:ai-recommendations'])
    ->post('/health/analysis-v2', [AiRecommendationController::class, 'analyze']);
