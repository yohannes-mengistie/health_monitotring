# End-to-End Implementation Overview

## Purpose

This project implements a full pipeline for live health monitoring: sensor data from an Arduino flows through a USB bridge, into a Laravel API, then into ML services for risk prediction and clinical feedback, and finally back to a Flutter client for display and user interaction.

## High-Level Architecture

- Hardware: Arduino-based sensor device (heart rate, SpO2, temperature, optional BP).
- USB bridge: Python serial listener with a Flask API to receive auth tokens.
- Backend: Laravel API with authentication, ingestion, aggregation, risk scoring, and analytics.
- ML services: FastAPI services for risk prediction and AI clinical report generation.
- Mobile client: Flutter app for auth, live vitals, metrics, and recommendations.

Ports and defaults:

- Laravel API: http://127.0.0.1:8000/api
- USB bridge (Flask): http://127.0.0.1:5001
- ML risk model (FastAPI): http://127.0.0.1:5000
- Clinical report generator (FastAPI): http://127.0.0.1:9000

## End-to-End Data Flow

1. User signs in on the Flutter app.
2. The app receives a Sanctum token from Laravel and stores it locally.
3. The app sends the token to the USB bridge (Flask) using /set-token.
4. The USB bridge listens to the serial port, parses vitals, and forwards them to Laravel as authenticated requests.
5. Laravel buffers samples for 15 seconds, averages the window, and calls the ML risk service.
6. Laravel optionally calls the clinical report service for a user-friendly summary.
7. Laravel persists the final record and provides live/metrics endpoints to the app.
8. The app polls live status, shows latest vitals and risk, and can request detailed recommendations.

## USB Bridge: serial_listener.py

Responsibilities:

- Reads serial lines from /dev/ttyACM0 at 115200 baud.
- Parses two formats:
  - BPM:75.0,SPO2:98.0,TEMP:36.5
  - BPM: 72.8 | SpO2: 96% | Temp: 28.5C | BP: 122/84 mmHg
- Holds the current auth token in memory and in last_token.json.
- Forwards payloads to Laravel /api/health-data with the bearer token.
- Provides a Flask endpoint for the mobile app to set the token.

Key endpoints:

- POST /set-token
  - Body: {"token": "<sanctum-token>"}
  - Stores token in memory and cache file

Token flow:

- The mobile app calls /set-token after login.
- The bridge uses this token to authenticate all sensor uploads.

## Laravel Backend

### API Routes

Routes are defined in routes/api.php:

- POST /register
- POST /login
- GET /user (auth required)
- POST /health-data (auth required)
- GET /health/analysis (auth required)
- GET|POST /health/analysis-v2 (auth required)
- GET /health/live-status (auth required)
- GET /health/metrics-overview (auth required)
- GET /health/metrics-history (auth required)
- PATCH /update (auth required)

### Authentication

- Login: returns a Sanctum token.
- The token is required for all sensor ingestion and data retrieval endpoints.

### Health Ingestion Pipeline

Implemented in SensorController::ingest:

- Validates incoming vitals.
- Stores the latest raw sample in cache for live status.
- Buffers samples for a 15-second window.
- After the window, averages vitals and triggers a 3-second cooldown.
- Builds an ML payload using user profile data (age, gender, weight, height).

Safety and post-processing:

- Applies a WHO-inspired safety layer to adjust risk when vitals are stable.
- Persists the final record in HealthData.

### ML Integration

Risk prediction:

- POST http://127.0.0.1:5000/predict
- The request includes averaged vitals and user demographics.
- The response includes predicted_risk, probabilities, and derived metrics (BMI, MAP).

Clinical report generation:

- POST http://127.0.0.1:9000/generate-clinical-report
- Laravel sends the latest averaged vitals and derived features.
- The response includes a natural language clinical summary.
- Cached for 30 minutes per user and record.

### AI Recommendation Service (Laravel)

Laravel provides an AI recommendation path that is independent from the FastAPI clinical report.
This is implemented with AiRecommendationService and exposed via AiRecommendationController.

How it works:

- Endpoint: /health/analysis-v2 (GET or POST)
- The controller validates vitals, accepts optional context (user note, current feeling, structured assessment),
  and delegates to AiRecommendationService.
- AiRecommendationService uses the Ollama client to generate a triage-style response.
- If the requested language is Amharic, it translates the response using LibreTranslate
  (with a MyMemory fallback).
- The controller stores structured assessments in ClinicalAssessment for audit and review.

Ollama configuration:

- config/ollama-laravel.php sets model, URL, keep-alive, and optional API key.
- The service attempts fallback models if the preferred one fails.

### Live Status and Analytics

- GET /health/live-status
  - Returns either the raw cached sample (near real-time) or the latest averaged record.
  - Includes measurement phase and remaining seconds.

- GET /health/metrics-overview
  - Aggregates and trends vitals for day/week/month/year.

- GET /health/metrics-history
  - Returns chart-ready points for vitals history.

## ML Risk Model Service: model_service.py

Responsibilities:

- Loads a trained classifier and feature schema.
- Computes derived metrics (pulse pressure, MAP, BMI).
- Predicts risk and returns probabilities.
- Flags a risk alert when the model predicts high risk or high probability.

Endpoint:

- POST /predict
  - Input: vitals + demographics + patient_id
  - Output: predicted_risk, probabilities, derived metrics


## Flutter Client (health-app)

### Authentication

- Uses /register and /login endpoints.
- Saves the token in SharedPreferences.
- Sends the token to the USB bridge using TokenBridgeService.

### Live Monitoring

- Calls GET /health/live-status.
- Displays live vitals, risk label, and measurement phase.
- Caches the last successful live payload for offline display.

### Recommendations

- Calls /health/analysis-v2 with optional context (user note, current feeling, structured assessment).
- Falls back to /health/analysis if needed.

### Metrics

- Calls /health/metrics-overview and /health/metrics-history to render trends.

### Mock Data Support

- The app includes a MockHealthService for demo data.
- The live dashboard and metrics paths are built to consume backend APIs.

## Data Persistence

Laravel models:

- HealthData: stores vitals, derived metrics, risk, and probabilities.
- ClinicalAssessment: stores structured user symptom context and AI outputs.

## Configuration Summary

USB bridge:

- LARAVEL_API_URL: base /api/health-data endpoint
- LARAVEL_USER_API_URL: used to validate the token via /api/user

Flutter app:

- API_BASE_URL: Laravel API base URL
- USB_BRIDGE_URL: Flask bridge URL
- AI_RECOMMENDATION_BASE_URL: optional dedicated AI endpoint

ML services:

- model_service.py expects model artifacts (clinical_risk_model.pkl, etc.)
- feedback_service.py expects model artifacts and Gemini credentials

## What Happens in a Typical Session

1. User registers or logs in on the Flutter app.
2. App stores token and sends it to the USB bridge.
3. Arduino streams vitals to the serial listener.
4. Listener forwards samples to Laravel with auth.
5. Laravel buffers and averages for 15 seconds, then calls ML services.
6. Laravel writes the final record and returns live status.
7. App shows live vitals, risk level, and AI recommendations.

## Notes for the Report

- The serial listener is the only component that touches USB hardware.
- The token bridge decouples device streaming from mobile authentication.
- Laravel is the system hub: it validates, aggregates, calls ML, and serves the app.
- ML services are isolated, fast, and versionable without changing the main API.
- The app is designed for real-time display but retains a fallback cache for UX stability.
