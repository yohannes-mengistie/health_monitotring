class ApiConfig {
  // Production backend hosted on Render. Override locally with:
  // --dart-define=API_BASE_URL=http://<host>:8000/api
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://health-monitoring-api.onrender.com/api',
  );

  // Dedicated AI recommendation endpoint. Same host as the main API in
  // production; override at build time if it diverges:
  // --dart-define=AI_RECOMMENDATION_BASE_URL=https://<your-host>
  static const String aiRecommendationBaseUrl = String.fromEnvironment(
    'AI_RECOMMENDATION_BASE_URL',
    defaultValue: 'https://health-monitoring-api.onrender.com/api',
  );

  // Override when your AI route path differs from /health/analysis-v2.
  // Example: --dart-define=AI_RECOMMENDATION_PATH=/api/health/analysis-v2
  static const String aiRecommendationPath = String.fromEnvironment(
    'AI_RECOMMENDATION_PATH',
    defaultValue: '/health/analysis-v2',
  );

  // USB bridge runs locally on the developer's machine alongside the serial
  // listener; not deployable. Override at build time with:
  // --dart-define=USB_BRIDGE_URL=http://<host>:5001
  static const String usbBridgeUrl = String.fromEnvironment(
    'USB_BRIDGE_URL',
    defaultValue: 'http://127.0.0.1:5001',
  );
}
