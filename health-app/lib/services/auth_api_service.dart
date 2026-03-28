import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:health_monitor_ai/config/api_config.dart';
import 'package:http/http.dart' as http;

class AuthApiService {
  final http.Client _client;

  AuthApiService({http.Client? client}) : _client = client ?? http.Client();

  Future<void> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String dob,
    required String gender,
    required double weight,
    required double height,
    required double diastolicBp,
    required double systolicBp,
  }) async {
    final response = await _client.post(
      Uri.parse('${ApiConfig.baseUrl}/register'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
        'dob': dob,
        'gender': gender,
        'weight': weight,
        'height': height,
        'diastolic_bp': diastolicBp,
        'systolic_bp': systolicBp,
      }),
    );

    _ensureSuccess(response);
  }

  Future<String> login(
      {required String email, required String password}) async {
    final loginUrl = Uri.parse('${ApiConfig.baseUrl}/login');
    final response = await _client.post(
      loginUrl,
      headers: _jsonHeaders,
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final data = _ensureSuccess(response);
    if (kDebugMode) {
      debugPrint('[AUTH] Login URL: $loginUrl');
      debugPrint('[AUTH] Login status: ${response.statusCode}');
      final responsePreview = response.body.length > 400
          ? '${response.body.substring(0, 400)}...'
          : response.body;
      debugPrint('[AUTH] Login raw response: $responsePreview');
      debugPrint('[AUTH] Login response keys: ${data.keys.toList()}');
    }

    final token = _extractAccessToken(data);
    if (token == null || token.isEmpty) {
      throw Exception(
        'Login succeeded but no access token was returned. '
        'Expected one of: access_token, token, data.access_token, data.token.',
      );
    }

    return token;
  }

  Future<Map<String, dynamic>> fetchCurrentUser(String token) async {
    final response = await _client.get(
      Uri.parse('${ApiConfig.baseUrl}/user'),
      headers: {
        ..._jsonHeaders,
        'Authorization': 'Bearer $token',
      },
    );

    final data = _ensureSuccess(response);
    if (data['data'] is Map<String, dynamic>) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> updateProfile({
    required String token,
    String? firstName,
    String? lastName,
    String? gender,
    double? weight,
    double? height,
    double? systolicBp,
    double? diastolicBp,
    String? dob,
  }) async {
    final payload = <String, dynamic>{
      if (firstName != null && firstName.trim().isNotEmpty)
        'first_name': firstName.trim(),
      if (lastName != null && lastName.trim().isNotEmpty)
        'last_name': lastName.trim(),
      if (gender != null && gender.trim().isNotEmpty) 'gender': gender.trim(),
      if (weight != null) 'weight': weight,
      if (height != null) 'height': height,
      if (systolicBp != null) 'systolic_bp': systolicBp,
      if (diastolicBp != null) 'diastolic_bp': diastolicBp,
      if (dob != null && dob.trim().isNotEmpty) 'dob': dob.trim(),
    };

    final response = await _client.patch(
      Uri.parse('${ApiConfig.baseUrl}/update'),
      headers: {
        ..._jsonHeaders,
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    final data = _ensureSuccess(response);
    if (data['data'] is Map<String, dynamic>) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }

    return Map<String, dynamic>.from(data);
  }

  Map<String, String> get _jsonHeaders => const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _ensureSuccess(http.Response response) {
    final body = _decodeResponseBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw Exception(_extractErrorMessage(body, response.statusCode));
  }

  Map<String, dynamic> _decodeResponseBody(String body) {
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

  String _extractErrorMessage(Map<String, dynamic> body, int statusCode) {
    final validationErrors = body['errors'];
    if (validationErrors is Map<String, dynamic>) {
      final firstErrorList = validationErrors.values.firstWhere(
        (value) => value is List && value.isNotEmpty,
        orElse: () => null,
      );

      if (firstErrorList is List && firstErrorList.isNotEmpty) {
        return firstErrorList.first.toString();
      }
    }

    final message = body['message']?.toString();
    if (message != null && message.isNotEmpty) {
      return message;
    }

    return 'Request failed with status code $statusCode';
  }

  String? _extractAccessToken(Map<String, dynamic> body) {
    final topLevelToken =
        body['access_token'] ?? body['token'] ?? body['accessToken'];
    if (topLevelToken != null && topLevelToken.toString().isNotEmpty) {
      return topLevelToken.toString();
    }

    final nestedData = body['data'];
    if (nestedData is Map<String, dynamic>) {
      final nestedToken = nestedData['access_token'] ??
          nestedData['token'] ??
          nestedData['accessToken'];
      if (nestedToken != null && nestedToken.toString().isNotEmpty) {
        return nestedToken.toString();
      }
    }

    return null;
  }
}
