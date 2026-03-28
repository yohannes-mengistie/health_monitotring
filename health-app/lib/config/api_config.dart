class ApiConfig {
  // Override at build time with:
  // --dart-define=API_BASE_URL=http://<host>:8000/api
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  // Override at build time with:
  // --dart-define=USB_BRIDGE_URL=http://<host>:5001
  static const String usbBridgeUrl = String.fromEnvironment(
    'USB_BRIDGE_URL',
    defaultValue: 'http://127.0.0.1:5001',
  );
}
