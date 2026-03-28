import 'dart:convert';

import 'package:health_monitor_ai/config/api_config.dart';
import 'package:http/http.dart' as http;

class TokenBridgeService {
  final http.Client _client;

  TokenBridgeService({http.Client? client}) : _client = client ?? http.Client();

  Future<void> setBridgeToken(String? token) async {
    final response = await _client.post(
      Uri.parse('${ApiConfig.usbBridgeUrl}/set-token'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'token': token}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'USB bridge token sync failed with status ${response.statusCode}',
      );
    }
  }
}
