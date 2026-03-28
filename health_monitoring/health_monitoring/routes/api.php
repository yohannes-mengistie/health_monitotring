<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\SensorController;
use App\Http\Controllers\Auth\RegisterController;
use App\Http\Controllers\Auth\LoginController;

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/health-data', [SensorController::class, 'ingest']);
    Route::get('/user', [RegisterController::class, 'index']);
    Route::get('/health/analysis', [SensorController::class, 'getDetailedAnalysis']);
    Route::get('/health/live-status', [SensorController::class, 'getLiveStatus']);
    Route::get('/health/metrics-overview', [SensorController::class, 'getMetricsOverview']);
    Route::patch('/update',[SensorController::class, 'update']);
});

Route::post('/register', [RegisterController::class, 'store']);
Route::post('/login', [LoginController::class, 'login']);
