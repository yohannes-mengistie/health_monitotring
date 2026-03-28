import 'dart:convert';

import 'package:health_monitor_ai/config/api_config.dart';
import 'package:http/http.dart' as http;

class HealthApiService {
  final http.Client _client;

  HealthApiService({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, dynamic>> fetchMetricsOverview({
    required String token,
    required String period,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/health/metrics-overview?period=$period',
    );

    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw Exception(body['message']?.toString() ?? 'Unable to load metrics.');
  }

  Future<Map<String, dynamic>> fetchDashboardSummary({
    required String token,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/health/live-status');

    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw Exception(
        body['message']?.toString() ?? 'Unable to load dashboard data.');
  }

  Future<Map<String, dynamic>> fetchLiveVitalsAndRisk({
    required String token,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/health/live-status');

    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw Exception(
        body['message']?.toString() ?? 'Unable to load live vitals data.');
  }

  Future<Map<String, dynamic>> fetchDetailedAnalysis({
    required String token,
    required String language,
  }) async {
    final uri =
        Uri.parse('${ApiConfig.baseUrl}/health/analysis?lang=$language');

    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw Exception(
      body['error']?.toString() ??
          body['message']?.toString() ??
          'Unable to load clinical recommendations.',
    );
  }

  Map<String, dynamic> _decodeBody(String body) {
    if (body.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{'data': decoded};
    } catch (_) {
      return <String, dynamic>{'message': body};
    }
  }
}
