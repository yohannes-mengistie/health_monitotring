import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:health_monitor_ai/config/api_config.dart';
import 'package:http/http.dart' as http;

class HealthApiService {
  final http.Client _client;

  HealthApiService({http.Client? client}) : _client = client ?? http.Client();

  Uri _buildUrl(String base, String path) {
    final normalizedBase =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

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

    if (kDebugMode) {
      debugPrint('[METRICS] URL: $uri');
      debugPrint('[METRICS] Status: ${response.statusCode}');
      final preview = response.body.length > 300
          ? '${response.body.substring(0, 300)}...'
          : response.body;
      debugPrint('[METRICS] Body preview: $preview');
    }

    final body = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw Exception(body['message']?.toString() ?? 'Unable to load metrics.');
  }

  Future<Map<String, dynamic>> fetchMetricsHistory({
    required String token,
    required String period,
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/health/metrics-history?period=$period',
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

    throw Exception(body['message']?.toString() ?? 'Unable to load history.');
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

  Future<Map<String, dynamic>> fetchDetailedAnalysisV2({
    required String token,
    String? language,
    String? userPrompt,
    String? currentFeeling,
    String? historySummary,
    Map<String, dynamic>? latestVitals,
    Map<String, dynamic>? structuredAssessment,
  }) async {
    final dedicatedUri = _buildUrl(
      ApiConfig.aiRecommendationBaseUrl,
      ApiConfig.aiRecommendationPath,
    );
    final fallbackUri = _buildUrl(ApiConfig.baseUrl, '/health/analysis-v2');

    final shouldSendContext = ((userPrompt?.trim().isNotEmpty ?? false) ||
            (currentFeeling?.trim().isNotEmpty ?? false) ||
            (historySummary?.trim().isNotEmpty ?? false) ||
            structuredAssessment != null) &&
        latestVitals != null;

    Future<Map<String, dynamic>> send(Uri uri) async {
      late final http.Response response;
      final normalizedLanguage = language?.trim();
      final languageQuery =
          (normalizedLanguage == null || normalizedLanguage.isEmpty)
              ? null
              : normalizedLanguage;
      final effectiveUri = languageQuery == null
          ? uri
          : uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                'language': languageQuery,
              },
            );

      if (shouldSendContext) {
        final payload = <String, dynamic>{
          'bpm': latestVitals['bpm'],
          'spo2': latestVitals['spo2'],
          'temperature': latestVitals['temperature'],
          'systolic_bp': latestVitals['systolic_bp'],
          'diastolic_bp': latestVitals['diastolic_bp'],
          if (languageQuery != null) 'language': languageQuery,
          if (userPrompt != null && userPrompt.trim().isNotEmpty)
            'user_note': userPrompt.trim(),
          if (currentFeeling != null && currentFeeling.trim().isNotEmpty)
            'current_feeling': currentFeeling.trim(),
          if (historySummary != null && historySummary.trim().isNotEmpty)
            'history_summary': historySummary.trim(),
          if (structuredAssessment != null)
            'structured_assessment': structuredAssessment,
        };

        response = await _client.post(
          effectiveUri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        );
      } else {
        response = await _client.get(
          effectiveUri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      }

      final body = _decodeBody(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return body;
      }

      throw Exception(
        body['error']?.toString() ??
            body['message']?.toString() ??
            'Unable to load AI recommendation (v2).',
      );
    }

    try {
      return await send(dedicatedUri);
    } catch (firstError) {
      // If a dedicated AI URL is unavailable, fallback to the main API host.
      if (kDebugMode) {
        debugPrint('[AI-V2] Dedicated URL failed: $dedicatedUri');
        debugPrint('[AI-V2] Error: $firstError');
        debugPrint('[AI-V2] Falling back to: $fallbackUri');
      }

      return send(fallbackUri);
    }
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
