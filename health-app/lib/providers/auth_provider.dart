import 'package:flutter/foundation.dart';
import 'package:health_monitor_ai/models/user_model.dart';
import 'package:health_monitor_ai/services/auth_api_service.dart';
import 'package:health_monitor_ai/services/token_bridge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
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

  User? get currentUser => _currentUser;
  String? get authToken => _authToken;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null && _authToken != null;
  String? get errorMessage => _errorMessage;

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
      await prefs.setString('auth_token', _authToken!);
      await _syncTokenToBridge(_authToken);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
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
    required double diastolicBp,
    required double systolicBp,
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
        diastolicBp: diastolicBp,
        systolicBp: systolicBp,
      );

      final token =
          await _authApiService.login(email: email, password: password);
      final backendUser = await _authApiService.fetchCurrentUser(token);

      _authToken = token;
      _currentUser = _mapBackendUserToAppUser(backendUser, fallbackAge: age);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _authToken!);
      await _syncTokenToBridge(_authToken);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await _syncTokenToBridge(null);

      _currentUser = null;
      _authToken = null;
      _errorMessage = null;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> checkAuthStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token != null) {
        try {
          final backendUser = await _authApiService.fetchCurrentUser(token);
          _authToken = token;
          _currentUser = _mapBackendUserToAppUser(backendUser);
          await _syncTokenToBridge(_authToken);
        } catch (_) {
          await prefs.remove('auth_token');
          _authToken = null;
          _currentUser = null;
          await _syncTokenToBridge(null);
        }
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
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
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
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
