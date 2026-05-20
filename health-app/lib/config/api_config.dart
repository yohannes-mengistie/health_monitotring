class ApiConfig {
  // Override at build time with:
  // --dart-define=API_BASE_URL=http://<host>:8000/api
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  // Dedicated AI recommendation endpoint (Ollama proxy/tunnel).
  // Override at build time with:
  // --dart-define=AI_RECOMMENDATION_BASE_URL=https://<your-ngrok-or-api-host>
  static const String aiRecommendationBaseUrl = String.fromEnvironment(
    'AI_RECOMMENDATION_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  // Override when your AI route path differs from /health/analysis-v2.
  // Example: --dart-define=AI_RECOMMENDATION_PATH=/api/health/analysis-v2
  static const String aiRecommendationPath = String.fromEnvironment(
    'AI_RECOMMENDATION_PATH',
    defaultValue: '/health/analysis-v2',
  );

  // Override at build time with:
  // --dart-define=USB_BRIDGE_URL=http://<host>:5001
  static const String usbBridgeUrl = String.fromEnvironment(
    'USB_BRIDGE_URL',
    defaultValue: 'http://127.0.0.1:5001',
  );
}
