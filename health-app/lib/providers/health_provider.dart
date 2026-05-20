import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:health_monitor_ai/models/vitals_model.dart';
import 'package:health_monitor_ai/models/analysis_model.dart';
import 'package:health_monitor_ai/models/recommendation_model.dart';
import 'package:health_monitor_ai/services/health_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HealthProvider extends ChangeNotifier {
  static const String _liveCachePrefix = 'live_cache_v1';
  final HealthApiService _healthApiService;

  HealthProvider({HealthApiService? healthApiService})
      : _healthApiService = healthApiService ?? HealthApiService();

  VitalReading? _currentVitals;
  List<VitalReading> _vitalsHistory = [];
  HealthAnalysis? _currentAnalysis;
  HealthRecommendation? _currentRecommendation;
  double _avgHeartRate = 0;
  double _avgSpo2 = 0;
  double _heartRateTrendPercent = 0;
  double _spo2TrendPercent = 0;
  int _systolicBp = 0;
  int _diastolicBp = 0;
  double _temperature = 0;
  bool _metricsUsingBackend = false;
  String _metricsPeriod = 'week';
  Map<String, dynamic>? _metricsOverviewData;
  String _livePhase = 'measuring';
  int _livePhaseRemainingSeconds = 0;
  String _liveInstruction = 'Measuring... keep your hand steady.';
  bool _isUsingCachedData = false;
  DateTime? _cachedAt;
  bool _isLoading = false;
  String? _errorMessage;
  String _lastUserPrompt = '';
  String _lastCurrentFeeling = '';
  String _lastStructuredAssessmentJson = '';

  VitalReading? get currentVitals => _currentVitals;
  List<VitalReading> get vitalsHistory => _vitalsHistory;
  HealthAnalysis? get currentAnalysis => _currentAnalysis;
  HealthRecommendation? get currentRecommendation => _currentRecommendation;
  double get avgHeartRate => _avgHeartRate;
  double get avgSpo2 => _avgSpo2;
  double get heartRateTrendPercent => _heartRateTrendPercent;
  double get spo2TrendPercent => _spo2TrendPercent;
  int get systolicBp => _systolicBp;
  int get diastolicBp => _diastolicBp;
  double get temperature => _temperature;
  bool get metricsUsingBackend => _metricsUsingBackend;
  String get metricsPeriod => _metricsPeriod;
  Map<String, dynamic>? get metricsOverviewData => _metricsOverviewData;
  String get livePhase => _livePhase;
  int get livePhaseRemainingSeconds => _livePhaseRemainingSeconds;
  String get liveInstruction => _liveInstruction;
  bool get isUsingCachedData => _isUsingCachedData;
  DateTime? get cachedAt => _cachedAt;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get lastUserPrompt => _lastUserPrompt;
  String get lastCurrentFeeling => _lastCurrentFeeling;
  String get lastStructuredAssessmentJson => _lastStructuredAssessmentJson;

  void resetUserState() {
    _currentRecommendation = null;
    _vitalsHistory = [];
    _lastUserPrompt = '';
    _lastCurrentFeeling = '';
    _lastStructuredAssessmentJson = '';
    _errorMessage = null;
    _clearDashboard();
    _clearMetrics();
    notifyListeners();
  }

  Future<void> initializeHealth(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final restored = await _restoreLiveCache(userId);
      if (!restored) {
        _clearDashboard();
        _clearMetrics();
        _currentRecommendation = null;
        _errorMessage =
            'Live data only. Start the device stream to load vitals.';
      }
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshVitals(String userId) async {
    try {
      _errorMessage =
          'Live data only. Start the device stream to refresh vitals.';
    } catch (e) {
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  Future<void> updateTaskStatus(String taskId, TaskStatus newStatus) async {
    try {
      if (_currentRecommendation == null) return;

      final updatedTasks = _currentRecommendation!.tasks.map((task) {
        if (task.id == taskId) {
          return task.copyWith(status: newStatus);
        }
        return task;
      }).toList();

      final completedCount =
          updatedTasks.where((t) => t.status == TaskStatus.completed).length;

      _currentRecommendation = HealthRecommendation(
        id: _currentRecommendation!.id,
        userId: _currentRecommendation!.userId,
        actionPlan: _currentRecommendation!.actionPlan,
        totalGoals: _currentRecommendation!.totalGoals,
        completedGoals: completedCount,
        tasks: updatedTasks,
        expectedImpact: _currentRecommendation!.expectedImpact,
        medicalDisclaimer: _currentRecommendation!.medicalDisclaimer,
        createdAt: _currentRecommendation!.createdAt,
        updatedAt: DateTime.now(),
      );

      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<List<VitalReading>> getVitalsForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      return _vitalsHistory
          .where((v) =>
              v.timestamp.isAfter(startDate) && v.timestamp.isBefore(endDate))
          .toList();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return [];
    }
  }

  VitalsTrend? getVitalsTrendForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    try {
      final readings = _vitalsHistory
          .where((v) =>
              v.timestamp.isAfter(startDate) && v.timestamp.isBefore(endDate))
          .toList();

      if (readings.isEmpty) return null;

      return VitalsTrend(
        readings: readings,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> loadMetricsOverview({
    required String period,
    String? token,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _metricsPeriod = period;
    notifyListeners();

    try {
      if (token == null || token.isEmpty) {
        _clearMetrics();
        _errorMessage =
            'Authentication token is missing. Please sign in again.';
      } else {
        final response = await _healthApiService.fetchMetricsOverview(
          token: token,
          period: period,
        );

        if (_isValidMetricsResponse(response)) {
          _setMetricsFromBackend(response);
        } else {
          _clearMetrics();
          _errorMessage = _extractBackendMessage(response) ??
              'Metrics endpoint returned no usable data. If database has rows, verify you are signed in with the same account that produced those readings.';
        }
      }
    } catch (e) {
      _clearMetrics();
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> loadMetricsHistory({
    required String period,
    String? token,
  }) async {
    try {
      if (token == null || token.isEmpty) {
        _errorMessage = 'Authentication token is missing. Please sign in again.';
        notifyListeners();
        return [];
      }

      final response = await _healthApiService.fetchMetricsHistory(
        token: token,
        period: period,
      );

      final data = response['data'];
      if (data is Map<String, dynamic>) {
        return _asMapList(data['chart_points']);
      }

      return const <Map<String, dynamic>>[];
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return [];
    }
  }

  Future<void> loadLiveVitalsAndRisk({
    required String userId,
    String? token,
    bool showLoading = true,
  }) async {
    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      if (token == null || token.isEmpty) {
        _clearDashboard();
        _errorMessage =
            'Authentication token is missing. Please sign in again.';
      } else {
        final response =
            await _healthApiService.fetchLiveVitalsAndRisk(token: token);
        final data = response['data'];

        if (data is Map<String, dynamic> && _hasDashboardData(data)) {
          _setDashboardFromBackend(userId, data);
          await _saveLiveCache(userId);
        } else {
          final restored = await _restoreLiveCache(userId);
          if (restored) {
            _errorMessage =
                'Live connection unavailable. Showing last saved reading.';
          } else {
            _clearDashboard();
            _errorMessage = _extractBackendMessage(response) ??
                'No live data found yet. Start serial streaming to populate vitals.';
          }
        }
      }
    } catch (e) {
      final restored = await _restoreLiveCache(userId);
      if (restored) {
        _errorMessage = 'Live connection lost. Showing last saved reading.';
      } else {
        _clearDashboard();
        _errorMessage = e.toString();
      }
    }

    if (showLoading) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    notifyListeners();
  }

  Future<void> loadClinicalRecommendation({
    required String userId,
    String? token,
    required String language,
    String? userPrompt,
    String? currentFeeling,
    String? historySummary,
    Map<String, dynamic>? structuredAssessment,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final previousRecommendation = _currentRecommendation;

    try {
      if (token == null || token.isEmpty) {
        _currentRecommendation = previousRecommendation;
        _errorMessage =
            'Authentication token is missing. Please sign in again.';
      } else {
        final cleanedUserPrompt = userPrompt?.trim();
        final cleanedFeeling = currentFeeling?.trim();
        final cleanedStructuredAssessment = structuredAssessment == null
            ? null
            : Map<String, dynamic>.from(structuredAssessment);
        final computedHistory = (historySummary?.trim().isNotEmpty ?? false)
            ? historySummary!.trim()
            : _buildRecentHistorySummary();

        Map<String, dynamic> response;
        try {
          response = await _healthApiService.fetchDetailedAnalysisV2(
            token: token,
            language: language,
            userPrompt: cleanedUserPrompt,
            currentFeeling: cleanedFeeling,
            historySummary: computedHistory,
            latestVitals: _latestVitalsPayload(),
            structuredAssessment: cleanedStructuredAssessment,
          );
        } catch (_) {
          // Keep backward compatibility by falling back to legacy endpoint.
          response = await _healthApiService.fetchDetailedAnalysis(
            token: token,
            language: language,
          );
        }

        final report = _extractReportText(response);
        if (report == null || report.trim().isEmpty) {
          _currentRecommendation = previousRecommendation;
          _errorMessage = _extractBackendMessage(response) ??
              'Recommendation report is empty.';
        } else {
          final now = DateTime.now();
          _currentRecommendation = HealthRecommendation(
            id: 'backend_recommendation',
            userId: userId,
            actionPlan: report,
            totalGoals: 0,
            completedGoals: 0,
            tasks: const [],
            expectedImpact: const [],
            medicalDisclaimer:
                'This is an AI-generated educational summary. Please consult a qualified doctor for proper medical advice.',
            createdAt: now,
            updatedAt: now,
          );

          final rawRisk =
              (response['predicted_risk']?.toString() ?? '').toLowerCase();
          if (rawRisk.isNotEmpty && _currentAnalysis != null) {
            _currentAnalysis = HealthAnalysis(
              id: _currentAnalysis!.id,
              userId: _currentAnalysis!.userId,
              riskLevel: _mapRiskLevel(rawRisk),
              riskScore: _currentAnalysis!.riskScore,
              riskCategory: _currentAnalysis!.riskCategory,
              summary: _currentAnalysis!.summary,
              keyFinding: _currentAnalysis!.keyFinding,
              contributingFactors: _currentAnalysis!.contributingFactors,
              recentAlerts: _currentAnalysis!.recentAlerts,
              analysisData: _currentAnalysis!.analysisData,
              timestamp: _currentAnalysis!.timestamp,
            );
          }

          _errorMessage = null;
          _lastUserPrompt = cleanedUserPrompt ?? '';
          _lastCurrentFeeling = cleanedFeeling ?? '';
          _lastStructuredAssessmentJson = cleanedStructuredAssessment == null
              ? ''
              : const JsonEncoder.withIndent(
                  '  ',
                ).convert(cleanedStructuredAssessment);
        }
      }
    } catch (e) {
      _currentRecommendation = previousRecommendation;
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  @Deprecated('Use loadLiveVitalsAndRisk instead.')
  Future<void> loadDashboardSummary({
    required String userId,
    String? token,
  }) {
    return loadLiveVitalsAndRisk(userId: userId, token: token);
  }

  bool _isValidMetricsResponse(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      return false;
    }

    final pinnedMetrics = data['pinned_metrics'];
    final otherMetrics = data['other_metrics'];
    if (pinnedMetrics is! List || pinnedMetrics.isEmpty) {
      return false;
    }
    if (otherMetrics is! List || otherMetrics.isEmpty) {
      return false;
    }

    return true;
  }

  void _setMetricsFromBackend(Map<String, dynamic> payload) {
    final data = payload['data'] as Map<String, dynamic>;
    _metricsOverviewData = Map<String, dynamic>.from(data);
    final pinnedMetrics = _asMapList(data['pinned_metrics']);
    final otherMetrics = _asMapList(data['other_metrics']);

    final heartRateMetric = _findMetric(pinnedMetrics, 'heart_rate');
    final spo2Metric = _findMetric(pinnedMetrics, 'spo2');
    final bloodPressureMetric = _findMetric(otherMetrics, 'blood_pressure');
    final temperatureMetric = _findMetric(otherMetrics, 'temperature');

    _avgHeartRate = _toDouble(heartRateMetric?['value']);
    _avgSpo2 = _toDouble(spo2Metric?['value']);
    _heartRateTrendPercent = _toDouble(heartRateMetric?['trend_percent']);
    _spo2TrendPercent = _toDouble(spo2Metric?['trend_percent']);

    final bpValue = bloodPressureMetric?['value'];
    if (bpValue is Map<String, dynamic>) {
      _systolicBp = _toDouble(bpValue['systolic']).round();
      _diastolicBp = _toDouble(bpValue['diastolic']).round();
    } else {
      _systolicBp = 0;
      _diastolicBp = 0;
    }

    _temperature = _toDouble(temperatureMetric?['value']);
    _metricsUsingBackend = true;
    _errorMessage = null;
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((entry) => entry.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Map<String, dynamic>? _findMetric(
      List<Map<String, dynamic>> items, String key) {
    for (final item in items) {
      if (item['key']?.toString() == key) {
        return item;
      }
    }
    return items.isNotEmpty ? items.first : null;
  }

  bool _hasDashboardData(Map<String, dynamic> data) {
    return data['latest_vitals'] is Map<String, dynamic> &&
        data['risk'] is Map<String, dynamic>;
  }

  void _setDashboardFromBackend(String userId, Map<String, dynamic> data) {
    final latestVitals = data['latest_vitals'] as Map<String, dynamic>;
    final risk = data['risk'] as Map<String, dynamic>;

    final riskLabel =
        (risk['predicted_risk']?.toString() ?? 'low').toLowerCase();
    final probabilities = _asStringDoubleMap(risk['probabilities']);
    final riskLevel = _mapRiskLevel(riskLabel);
    final riskScore = _deriveRiskScore(probabilities, riskLabel);

    _currentVitals = VitalReading(
      id: 'backend_latest',
      userId: userId,
      heartRate: _toDouble(latestVitals['heart_rate']).round(),
      spo2: _toDouble(latestVitals['spo2']),
      systolicBP: _toDouble(latestVitals['systolic_bp']).round(),
      diastolicBP: _toDouble(latestVitals['diastolic_bp']).round(),
      temperature: _toDouble(latestVitals['temperature']),
      timestamp: DateTime.now(),
      deviceName: 'Backend Stream',
    );

    _currentAnalysis = HealthAnalysis(
      id: 'backend_analysis',
      userId: userId,
      riskLevel: riskLevel,
      riskScore: riskScore,
      riskCategory: 'Clinical Risk',
      summary:
          'Risk is inferred from latest ML prediction and probability distribution.',
      keyFinding: 'Predicted risk: ${risk['predicted_risk']}',
      contributingFactors: const [],
      recentAlerts: const [],
      analysisData: {
        'predicted_risk': risk['predicted_risk'],
        'probabilities': probabilities,
        'alert': risk['alert'] == true,
      },
      timestamp: DateTime.now(),
    );

    _avgHeartRate = _toDouble(latestVitals['heart_rate']);
    _avgSpo2 = _toDouble(latestVitals['spo2']);
    _systolicBp = _toDouble(latestVitals['systolic_bp']).round();
    _diastolicBp = _toDouble(latestVitals['diastolic_bp']).round();
    _temperature = _toDouble(latestVitals['temperature']);

    final rawPhase = data['phase']?.toString().toLowerCase();
    _livePhase = rawPhase == 'cooldown' ? 'cooldown' : 'measuring';

    final rawRemaining = _toDouble(data['remaining_seconds']).round();
    _livePhaseRemainingSeconds = rawRemaining < 0 ? 0 : rawRemaining;

    final rawInstruction = data['ui_message']?.toString().trim();
    if (rawInstruction != null && rawInstruction.isNotEmpty) {
      _liveInstruction = rawInstruction;
    } else {
      _liveInstruction = _livePhase == 'cooldown'
          ? 'Remove your hand. Wait 3 seconds, then place it again.'
          : 'Measuring... keep your hand steady.';
    }

    _metricsUsingBackend = true;
    _isUsingCachedData = false;
    _cachedAt = null;
    _errorMessage = null;
  }

  String _liveCacheKey(String userId) {
    return '${_liveCachePrefix}_$userId';
  }

  Future<void> _saveLiveCache(String userId) async {
    final vitals = _currentVitals;
    final analysis = _currentAnalysis;
    if (vitals == null || analysis == null) {
      return;
    }

    final payload = <String, dynamic>{
      'user_id': userId,
      'saved_at': DateTime.now().toIso8601String(),
      'vitals': {
        'heart_rate': vitals.heartRate,
        'spo2': vitals.spo2,
        'systolic_bp': vitals.systolicBP,
        'diastolic_bp': vitals.diastolicBP,
        'temperature': vitals.temperature,
        'timestamp': vitals.timestamp.toIso8601String(),
        'device_name': vitals.deviceName,
      },
      'analysis': {
        'risk_level': analysis.riskLevel.name,
        'risk_score': analysis.riskScore,
        'risk_category': analysis.riskCategory,
        'summary': analysis.summary,
        'key_finding': analysis.keyFinding,
        'analysis_data': analysis.analysisData,
        'timestamp': analysis.timestamp.toIso8601String(),
      },
      'live': {
        'phase': _livePhase,
        'remaining_seconds': _livePhaseRemainingSeconds,
        'instruction': _liveInstruction,
      },
      'metrics': {
        'avg_heart_rate': _avgHeartRate,
        'avg_spo2': _avgSpo2,
        'systolic_bp': _systolicBp,
        'diastolic_bp': _diastolicBp,
        'temperature': _temperature,
      },
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_liveCacheKey(userId), jsonEncode(payload));
  }

  Future<bool> _restoreLiveCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_liveCacheKey(userId));
    if (raw == null || raw.isEmpty) {
      return false;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      final cachedUser = decoded['user_id']?.toString();
      if (cachedUser != null && cachedUser != userId) {
        return false;
      }

      final vitals = decoded['vitals'];
      final analysis = decoded['analysis'];
      if (vitals is! Map<String, dynamic> ||
          analysis is! Map<String, dynamic>) {
        return false;
      }

      _currentVitals = VitalReading(
        id: 'cached_latest',
        userId: userId,
        heartRate: _toDouble(vitals['heart_rate']).round(),
        spo2: _toDouble(vitals['spo2']),
        systolicBP: _toDouble(vitals['systolic_bp']).round(),
        diastolicBP: _toDouble(vitals['diastolic_bp']).round(),
        temperature: _toDouble(vitals['temperature']),
        timestamp: DateTime.tryParse(
              vitals['timestamp']?.toString() ?? '',
            ) ??
            DateTime.now(),
        deviceName: vitals['device_name']?.toString() ?? 'Cached',
      );

      final riskLevel = _mapRiskLevel(analysis['risk_level']?.toString() ?? '');
      _currentAnalysis = HealthAnalysis(
        id: 'cached_analysis',
        userId: userId,
        riskLevel: riskLevel,
        riskScore: _toDouble(analysis['risk_score']),
        riskCategory: analysis['risk_category']?.toString() ?? 'Clinical Risk',
        summary: analysis['summary']?.toString() ?? 'Cached live risk summary.',
        keyFinding: analysis['key_finding']?.toString() ?? '',
        contributingFactors: const [],
        recentAlerts: const [],
        analysisData: Map<String, dynamic>.from(
          analysis['analysis_data'] is Map
              ? analysis['analysis_data'] as Map
              : <String, dynamic>{},
        ),
        timestamp: DateTime.tryParse(
              analysis['timestamp']?.toString() ?? '',
            ) ??
            DateTime.now(),
      );

      final live = decoded['live'];
      if (live is Map<String, dynamic>) {
        final rawPhase = live['phase']?.toString().toLowerCase();
        _livePhase = rawPhase == 'cooldown' ? 'cooldown' : 'measuring';
        _livePhaseRemainingSeconds =
            _toDouble(live['remaining_seconds']).round();
        final instruction = live['instruction']?.toString().trim();
        if (instruction != null && instruction.isNotEmpty) {
          _liveInstruction = instruction;
        }
      }

      final metrics = decoded['metrics'];
      if (metrics is Map<String, dynamic>) {
        _avgHeartRate = _toDouble(metrics['avg_heart_rate']);
        _avgSpo2 = _toDouble(metrics['avg_spo2']);
        _systolicBp = _toDouble(metrics['systolic_bp']).round();
        _diastolicBp = _toDouble(metrics['diastolic_bp']).round();
        _temperature = _toDouble(metrics['temperature']);
      }

      final savedAtRaw = decoded['saved_at']?.toString();
      _cachedAt = savedAtRaw == null
          ? _currentVitals?.timestamp
          : DateTime.tryParse(savedAtRaw) ?? _currentVitals?.timestamp;
      _metricsUsingBackend = true;
      _isUsingCachedData = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _clearDashboard() {
    _currentVitals = null;
    _currentAnalysis = null;
    _livePhase = 'measuring';
    _livePhaseRemainingSeconds = 0;
    _liveInstruction = 'Measuring... keep your hand steady.';
    _metricsUsingBackend = false;
    _isUsingCachedData = false;
    _cachedAt = null;
  }

  void _clearMetrics() {
    _avgHeartRate = 0;
    _avgSpo2 = 0;
    _heartRateTrendPercent = 0;
    _spo2TrendPercent = 0;
    _systolicBp = 0;
    _diastolicBp = 0;
    _temperature = 0;
    _metricsOverviewData = null;
    _metricsUsingBackend = false;
  }

  Map<String, double> _asStringDoubleMap(dynamic value) {
    if (value is! Map) {
      return <String, double>{};
    }

    final result = <String, double>{};
    value.forEach((key, val) {
      result[key.toString()] = _toDouble(val);
    });
    return result;
  }

  RiskLevel _mapRiskLevel(String rawRisk) {
    if (rawRisk.contains('critical')) return RiskLevel.critical;
    if (rawRisk.contains('high')) return RiskLevel.high;
    if (rawRisk.contains('moderate') || rawRisk.contains('medium')) {
      return RiskLevel.moderate;
    }
    return RiskLevel.low;
  }

  double _deriveRiskScore(Map<String, double> probabilities, String riskLabel) {
    if (probabilities.isNotEmpty) {
      final maxProb = probabilities.values.reduce((a, b) => a > b ? a : b);
      return (maxProb * 100).clamp(0, 100).toDouble();
    }

    return switch (_mapRiskLevel(riskLabel)) {
      RiskLevel.low => 25,
      RiskLevel.moderate => 55,
      RiskLevel.high => 80,
      RiskLevel.critical => 95,
    };
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _extractReportText(Map<String, dynamic> payload) {
    final recommendation = payload['recommendation'];
    if (recommendation != null && recommendation.toString().trim().isNotEmpty) {
      return recommendation.toString();
    }

    final topLevel = payload['report'];
    if (topLevel != null && topLevel.toString().trim().isNotEmpty) {
      return topLevel.toString();
    }

    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      final nestedRecommendation = data['recommendation'];
      if (nestedRecommendation != null &&
          nestedRecommendation.toString().trim().isNotEmpty) {
        return nestedRecommendation.toString();
      }

      final nested = data['report'];
      if (nested != null && nested.toString().trim().isNotEmpty) {
        return nested.toString();
      }
    }

    return null;
  }

  String? _extractBackendMessage(Map<String, dynamic> payload) {
    final topLevelMessage = payload['message']?.toString().trim();
    if (topLevelMessage != null && topLevelMessage.isNotEmpty) {
      return topLevelMessage;
    }

    final topLevelError = payload['error']?.toString().trim();
    if (topLevelError != null && topLevelError.isNotEmpty) {
      return topLevelError;
    }

    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      final nestedMessage = data['message']?.toString().trim();
      if (nestedMessage != null && nestedMessage.isNotEmpty) {
        return nestedMessage;
      }

      final nestedError = data['error']?.toString().trim();
      if (nestedError != null && nestedError.isNotEmpty) {
        return nestedError;
      }
    }

    return null;
  }

  Map<String, dynamic>? _latestVitalsPayload() {
    final vitals = _currentVitals;
    if (vitals == null) {
      if (_avgHeartRate == 0 && _avgSpo2 == 0 && _temperature == 0) {
        return null;
      }

      return <String, dynamic>{
        'bpm': _avgHeartRate.round(),
        'spo2': _avgSpo2,
        'temperature': _temperature,
        'systolic_bp': _systolicBp,
        'diastolic_bp': _diastolicBp,
      };
    }

    return <String, dynamic>{
      'bpm': vitals.heartRate,
      'spo2': vitals.spo2,
      'temperature': vitals.temperature,
      'systolic_bp': vitals.systolicBP,
      'diastolic_bp': vitals.diastolicBP,
    };
  }

  String _buildRecentHistorySummary() {
    if (_vitalsHistory.isEmpty) {
      if (_currentVitals == null) {
        return '';
      }

      final v = _currentVitals!;
      return 'Current vitals only: HR ${v.heartRate} bpm, SpO2 ${v.spo2.toStringAsFixed(1)}%, Temp ${v.temperature.toStringAsFixed(1)}C, BP ${v.systolicBP}/${v.diastolicBP}.';
    }

    final recent = _vitalsHistory.take(12).toList();
    final hrAvg =
        recent.map((r) => r.heartRate).reduce((a, b) => a + b) / recent.length;
    final spo2Avg =
        recent.map((r) => r.spo2).reduce((a, b) => a + b) / recent.length;
    final tempAvg = recent.map((r) => r.temperature).reduce((a, b) => a + b) /
        recent.length;
    final sbpAvg =
        recent.map((r) => r.systolicBP).reduce((a, b) => a + b) / recent.length;
    final dbpAvg = recent.map((r) => r.diastolicBP).reduce((a, b) => a + b) /
        recent.length;

    final latest = recent.first;

    return 'Recent trend (${recent.length} readings): avg HR ${hrAvg.toStringAsFixed(0)} bpm, avg SpO2 ${spo2Avg.toStringAsFixed(1)}%, avg Temp ${tempAvg.toStringAsFixed(1)}C, avg BP ${sbpAvg.toStringAsFixed(0)}/${dbpAvg.toStringAsFixed(0)}. Latest reading: HR ${latest.heartRate}, SpO2 ${latest.spo2.toStringAsFixed(1)}%, Temp ${latest.temperature.toStringAsFixed(1)}C, BP ${latest.systolicBP}/${latest.diastolicBP}.';
  }
}
