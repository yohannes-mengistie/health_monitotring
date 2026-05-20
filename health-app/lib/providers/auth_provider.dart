import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health_monitor_ai/config/api_config.dart';
import 'package:health_monitor_ai/models/user_model.dart';
import 'package:health_monitor_ai/services/auth_api_service.dart';
import 'package:health_monitor_ai/services/token_bridge_service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  static const String _authTokenKey = 'auth_token';
  static const String _cachedUserKey = 'cached_user';
  static const String _biometricEnabledKey = 'biometric_enabled';

  final AuthApiService _authApiService;
  final TokenBridgeService _tokenBridgeService;

  AuthProvider({
    AuthApiService? authApiService,
    TokenBridgeService? tokenBridgeService,
  })  : _authApiService = authApiService ?? AuthApiService(),
        _tokenBridgeService = tokenBridgeService ?? TokenBridgeService();

  User? _currentUser;
  String? _authToken;
  bool _isLoading = false;
  String? _errorMessage;
  bool _biometricEnabled = false;
  bool _biometricLoaded = false;

  User? get currentUser => _currentUser;
  String? get authToken => _authToken;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null && _authToken != null;
  String? get errorMessage => _errorMessage;
  bool get biometricEnabled => _biometricEnabled;

  Future<void> loadBiometricPreference() async {
    if (_biometricLoaded) return;

    final prefs = await SharedPreferences.getInstance();
    _biometricEnabled = prefs.getBool(_biometricEnabledKey) ?? false;
    _biometricLoaded = true;
    notifyListeners();
  }

  Future<bool> canUseBiometrics() async {
    final auth = LocalAuthentication();
    final supported = await auth.isDeviceSupported();
    final canCheck = await auth.canCheckBiometrics;
    return supported && canCheck;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    if (enabled) {
      final token = _authToken ?? prefs.getString(_authTokenKey);
      if (token == null || token.isEmpty) {
        throw Exception('Sign in first to enable biometric login.');
      }

      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      if (!supported || !canCheck) {
        throw Exception('Biometric authentication is not available on this device.');
      }

      final confirmed = await auth.authenticate(
        localizedReason: 'Confirm to enable biometric login',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!confirmed) {
        throw Exception('Biometric confirmation cancelled.');
      }
    }

    await prefs.setBool(_biometricEnabledKey, enabled);
    _biometricEnabled = enabled;
    _biometricLoaded = true;
    notifyListeners();
  }

  Future<void> loginWithBiometrics() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_biometricEnabledKey) ?? false;
      if (!enabled) {
        throw Exception('Biometric login is not enabled.');
      }

      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      if (!supported || !canCheck) {
        throw Exception('Biometric authentication is not available on this device.');
      }

      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to sign in',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!authenticated) {
        throw Exception('Biometric authentication failed.');
      }

      final token = prefs.getString(_authTokenKey);
      if (token == null || token.isEmpty) {
        throw Exception('No saved session. Please sign in first.');
      }

      _authToken = token;
      final cachedUser = _readCachedUser(prefs);
      if (cachedUser != null) {
        _currentUser = cachedUser;
      }

      try {
        final backendUser = await _authApiService.fetchCurrentUser(token);
        _currentUser = _mapBackendUserToAppUser(backendUser);
        await _saveCachedUser(prefs, _currentUser!);
        await _syncTokenToBridge(_authToken);
      } catch (e) {
        if (_isUnauthorizedError(e)) {
          await prefs.remove(_authTokenKey);
          await prefs.remove(_cachedUserKey);
          _authToken = null;
          _currentUser = null;
          await _syncTokenToBridge(null);
          throw Exception('Session expired. Please sign in again.');
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = _mapUserFriendlyError(e);
      _isLoading = false;
      notifyListeners();
      throw Exception(_errorMessage);
    }
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (email.isEmpty || password.isEmpty) {
        throw Exception('Email and password are required');
      }

      final token =
          await _authApiService.login(email: email, password: password);
      final backendUser = await _authApiService.fetchCurrentUser(token);

      _authToken = token;
      _currentUser = _mapBackendUserToAppUser(backendUser);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_authTokenKey, _authToken!);
      await _saveCachedUser(prefs, _currentUser!);
      await _syncTokenToBridge(_authToken);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = _mapUserFriendlyError(e);
      _isLoading = false;
      notifyListeners();
      throw Exception(_errorMessage);
    }
  }

  Future<void> signup({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String dob,
    required String gender,
    required double weight,
    required double height,
    required int age,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (firstName.isEmpty ||
          lastName.isEmpty ||
          email.isEmpty ||
          password.isEmpty ||
          passwordConfirmation.isEmpty ||
          dob.isEmpty ||
          gender.isEmpty) {
        throw Exception('All fields are required');
      }

      if (password != passwordConfirmation) {
        throw Exception('Password confirmation does not match');
      }

      await _authApiService.register(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
        passwordConfirmation: passwordConfirmation,
        dob: dob,
        gender: gender,
        weight: weight,
        height: height,
      );

      final token =
          await _authApiService.login(email: email, password: password);
      final backendUser = await _authApiService.fetchCurrentUser(token);

      _authToken = token;
      _currentUser = _mapBackendUserToAppUser(backendUser, fallbackAge: age);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_authTokenKey, _authToken!);
      await _saveCachedUser(prefs, _currentUser!);
      await _syncTokenToBridge(_authToken);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = _mapUserFriendlyError(e);
      _isLoading = false;
      notifyListeners();
      throw Exception(_errorMessage);
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_authTokenKey);
      await prefs.remove(_cachedUserKey);
      await _syncTokenToBridge(null);

      _currentUser = null;
      _authToken = null;
      _errorMessage = null;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = _mapUserFriendlyError(e);
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> checkAuthStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_authTokenKey);

      if (token == null || token.isEmpty) {
        _authToken = null;
        _currentUser = null;
        await _syncTokenToBridge(null);
        notifyListeners();
        return;
      }

      _authToken = token;
      final cachedUser = _readCachedUser(prefs);
      if (cachedUser != null) {
        _currentUser = cachedUser;
      }

      try {
        final backendUser = await _authApiService.fetchCurrentUser(token);
        _currentUser = _mapBackendUserToAppUser(backendUser);
        await _saveCachedUser(prefs, _currentUser!);
        await _syncTokenToBridge(_authToken);
      } catch (e) {
        if (_isUnauthorizedError(e)) {
          await prefs.remove(_authTokenKey);
          await prefs.remove(_cachedUserKey);
          _authToken = null;
          _currentUser = null;
          await _syncTokenToBridge(null);
        } else {
          // Keep cached auth for transient failures (offline/server down).
          await _syncTokenToBridge(_authToken);
        }
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = _mapUserFriendlyError(e);
      notifyListeners();
    }
  }

  Future<void> updateUserProfile(User updatedUser) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final token = _authToken;
      if (token == null || token.isEmpty) {
        throw Exception('You are not authenticated. Please log in again.');
      }

      final fullNameParts = updatedUser.fullName
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();
      final firstName = fullNameParts.isNotEmpty ? fullNameParts.first : null;
      final lastName =
          fullNameParts.length > 1 ? fullNameParts.sublist(1).join(' ') : null;

      final systolicBp =
          _extractBpValue(updatedUser.knownConditions, 'Systolic BP:');
      final diastolicBp =
          _extractBpValue(updatedUser.knownConditions, 'Diastolic BP:');

      final backendUser = await _authApiService.updateProfile(
        token: token,
        firstName: firstName,
        lastName: lastName,
        gender: updatedUser.gender,
        weight: updatedUser.weightKg,
        height: updatedUser.heightCm,
        systolicBp: systolicBp,
        diastolicBp: diastolicBp,
      );

      _currentUser = _mapBackendUserToAppUser(backendUser);
      final prefs = await SharedPreferences.getInstance();
      await _saveCachedUser(prefs, _currentUser!);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = _mapUserFriendlyError(e);
      _isLoading = false;
      notifyListeners();
      throw Exception(_errorMessage);
    }
  }

  String _mapUserFriendlyError(Object error) {
    if (error is AuthApiException) {
      return error.message;
    }

    if (error is SocketException) {
      return _networkHintMessage();
    }

    final text = error.toString();
    final lower = text.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable')) {
      return _networkHintMessage();
    }

    return text.replaceFirst('Exception: ', '').trim();
  }

  String _networkHintMessage() {
    return 'Cannot reach backend API from this phone. '
        'If running on a USB-debugged Android device, run: '
        'adb reverse tcp:8000 tcp:8000 and adb reverse tcp:5001 tcp:5001, '
        'then start app with --dart-define=API_BASE_URL=http://127.0.0.1:8000/api '
        'and --dart-define=USB_BRIDGE_URL=http://127.0.0.1:5001. '
        'Current API URL: ${ApiConfig.baseUrl}';
  }

  User _mapBackendUserToAppUser(
    Map<String, dynamic> backendUser, {
    int? fallbackAge,
  }) {
    final firstName = backendUser['first_name']?.toString().trim() ?? '';
    final lastName = backendUser['last_name']?.toString().trim() ?? '';
    final fullName = ('$firstName $lastName').trim();
    final dobRaw = backendUser['dob']?.toString();
    final dob = dobRaw == null ? null : DateTime.tryParse(dobRaw);

    return User(
      id: (backendUser['id'] ?? '').toString(),
      fullName: fullName.isEmpty ? 'User' : fullName,
      email: backendUser['email']?.toString() ?? '',
      age: fallbackAge ?? _calculateAgeFromDob(dob),
      gender: backendUser['gender']?.toString() ?? 'other',
      heightCm: _toDouble(backendUser['height']),
      weightKg: _toDouble(backendUser['weight']),
      activityLevel: ActivityLevel.moderate,
      knownConditions: [
        if (backendUser['systolic_bp'] != null)
          'Systolic BP: ${backendUser['systolic_bp']}',
        if (backendUser['diastolic_bp'] != null)
          'Diastolic BP: ${backendUser['diastolic_bp']}',
      ],
      currentMedications: const [],
      timezone: 'UTC',
      createdAt: _toDateTime(backendUser['created_at']),
      updatedAt: _toDateTime(backendUser['updated_at']),
    );
  }

  int _calculateAgeFromDob(DateTime? dob) {
    if (dob == null) return 0;

    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  DateTime _toDateTime(dynamic value) {
    final text = value?.toString();
    return DateTime.tryParse(text ?? '') ?? DateTime.now();
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _extractBpValue(List<String> knownConditions, String prefix) {
    final valueText = knownConditions
        .firstWhere(
          (item) => item.startsWith(prefix),
          orElse: () => '',
        )
        .replaceFirst(prefix, '')
        .trim();

    if (valueText.isEmpty) return null;
    return double.tryParse(valueText);
  }

  Future<void> _saveCachedUser(SharedPreferences prefs, User user) async {
    await prefs.setString(
      _cachedUserKey,
      jsonEncode(_userToJsonMap(user)),
    );
  }

  User? _readCachedUser(SharedPreferences prefs) {
    final raw = prefs.getString(_cachedUserKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return _userFromJsonMap(decoded);
    } catch (_) {
      return null;
    }
  }

  bool _isUnauthorizedError(Object error) {
    if (error is AuthApiException) {
      return error.statusCode == 401 || error.statusCode == 403;
    }

    final message = error.toString();
    return message.contains('401') || message.contains('403');
  }

  Map<String, dynamic> _userToJsonMap(User user) {
    return {
      'id': user.id,
      'fullName': user.fullName,
      'email': user.email,
      'age': user.age,
      'gender': user.gender,
      'heightCm': user.heightCm,
      'weightKg': user.weightKg,
      'activityLevel': user.activityLevel.name,
      'knownConditions': user.knownConditions,
      'currentMedications': user.currentMedications,
      'timezone': user.timezone,
      'createdAt': user.createdAt.toIso8601String(),
      'updatedAt': user.updatedAt.toIso8601String(),
    };
  }

  User _userFromJsonMap(Map<String, dynamic> json) {
    final knownConditions = (json['knownConditions'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];
    final currentMedications = (json['currentMedications'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];

    final levelName = json['activityLevel']?.toString();
    final activityLevel = ActivityLevel.values.firstWhere(
      (level) => level.name == levelName,
      orElse: () => ActivityLevel.moderate,
    );

    return User(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? 'User',
      email: json['email']?.toString() ?? '',
      age: _toInt(json['age']),
      gender: json['gender']?.toString() ?? 'other',
      heightCm: _toDouble(json['heightCm']),
      weightKg: _toDouble(json['weightKg']),
      activityLevel: activityLevel,
      knownConditions: knownConditions,
      currentMedications: currentMedications,
      timezone: json['timezone']?.toString() ?? 'UTC',
      createdAt: _toDateTime(json['createdAt']),
      updatedAt: _toDateTime(json['updatedAt']),
    );
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _syncTokenToBridge(String? token) async {
    try {
      await _tokenBridgeService.setBridgeToken(token);
      debugPrint('[AUTH] USB bridge token sync success');
    } catch (e) {
      // The bridge is optional for core auth; keep login/logout functional.
      debugPrint('[AUTH] USB bridge token sync failed: $e');
    }
  }
}
