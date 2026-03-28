import 'package:flutter/foundation.dart';
import 'package:health_monitor_ai/models/vitals_model.dart';
import 'package:health_monitor_ai/models/analysis_model.dart';
import 'package:health_monitor_ai/models/recommendation_model.dart';
import 'package:health_monitor_ai/services/health_api_service.dart';
import 'package:health_monitor_ai/services/mock_health_service.dart';

class HealthProvider extends ChangeNotifier {
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
  bool _isLoading = false;
  String? _errorMessage;

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
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> initializeHealth(String userId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Generate mock vitals
      _currentVitals =
          MockHealthService.generateMockVitalReading(userId: userId);

      // Generate mock history for trends
      _vitalsHistory = MockHealthService.generateMockVitalsHistory(
        userId: userId,
        days: 30,
      );

      // Generate analysis based on vitals
      _currentAnalysis = MockHealthService.generateMockAnalysis(
        userId: userId,
        recentReadings: _vitalsHistory.take(24).toList(),
      );

      // Generate recommendations based on analysis
      _currentRecommendation = MockHealthService.generateMockRecommendations(
        userId: userId,
        analysis: _currentAnalysis!,
      );

      _setMetricsFromFallback();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshVitals(String userId) async {
    try {
      // Generate new mock vitals reading
      _currentVitals =
          MockHealthService.generateMockVitalReading(userId: userId);

      // Add to history
      _vitalsHistory.insert(0, _currentVitals!);

      // Regenerate analysis
      _currentAnalysis = MockHealthService.generateMockAnalysis(
        userId: userId,
        recentReadings: _vitalsHistory.take(24).toList(),
      );

      // Regenerate recommendations
      _currentRecommendation = MockHealthService.generateMockRecommendations(
        userId: userId,
        analysis: _currentAnalysis!,
      );

      _setMetricsFromFallback();

      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
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
          _errorMessage =
              'Metrics endpoint returned no usable data. Waiting for live sensor readings.';
        }
      }
    } catch (e) {
      _clearMetrics();
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadLiveVitalsAndRisk({
    required String userId,
    String? token,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

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
        } else {
          _clearDashboard();
          _errorMessage =
              'No live data found yet. Start serial streaming to populate vitals.';
        }
      }
    } catch (e) {
      _clearDashboard();
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
    if (pinnedMetrics is! List || pinnedMetrics.length < 2) {
      return false;
    }
    if (otherMetrics is! List || otherMetrics.length < 2) {
      return false;
    }

    return true;
  }

  void _setMetricsFromBackend(Map<String, dynamic> payload) {
    final data = payload['data'] as Map<String, dynamic>;
    final pinnedMetrics =
        List<Map<String, dynamic>>.from(data['pinned_metrics'] as List);
    final otherMetrics =
        List<Map<String, dynamic>>.from(data['other_metrics'] as List);

    final heartRateMetric = pinnedMetrics.firstWhere(
      (item) => item['key']?.toString() == 'heart_rate',
      orElse: () => pinnedMetrics.first,
    );
    final spo2Metric = pinnedMetrics.firstWhere(
      (item) => item['key']?.toString() == 'spo2',
      orElse: () =>
          pinnedMetrics.length > 1 ? pinnedMetrics[1] : pinnedMetrics.first,
    );
    final bloodPressureMetric = otherMetrics.firstWhere(
      (item) => item['key']?.toString() == 'blood_pressure',
      orElse: () => otherMetrics.first,
    );
    final temperatureMetric = otherMetrics.firstWhere(
      (item) => item['key']?.toString() == 'temperature',
      orElse: () =>
          otherMetrics.length > 1 ? otherMetrics[1] : otherMetrics.first,
    );

    _avgHeartRate = _toDouble(heartRateMetric['value']);
    _avgSpo2 = _toDouble(spo2Metric['value']);
    _heartRateTrendPercent = _toDouble(heartRateMetric['trend_percent']);
    _spo2TrendPercent = _toDouble(spo2Metric['trend_percent']);

    final bpValue = bloodPressureMetric['value'];
    if (bpValue is Map<String, dynamic>) {
      _systolicBp = _toDouble(bpValue['systolic']).round();
      _diastolicBp = _toDouble(bpValue['diastolic']).round();
    } else {
      _systolicBp = 0;
      _diastolicBp = 0;
    }

    _temperature = _toDouble(temperatureMetric['value']);
    _metricsUsingBackend = true;
    _errorMessage = null;
  }

  void _setMetricsFromFallback() {
    final fallbackVitals = _currentVitals ??
        MockHealthService.generateMockVitalReading(userId: 'fallback_user');

    _avgHeartRate = fallbackVitals.heartRate.toDouble();
    _avgSpo2 = fallbackVitals.spo2;
    _heartRateTrendPercent = 2.0;
    _spo2TrendPercent = -0.3;
    _systolicBp = fallbackVitals.systolicBP;
    _diastolicBp = fallbackVitals.diastolicBP;
    _temperature = fallbackVitals.temperature;
    _metricsUsingBackend = false;
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
    _metricsUsingBackend = true;
    _errorMessage = null;
  }

  void _clearDashboard() {
    _currentVitals = null;
    _currentAnalysis = null;
    _metricsUsingBackend = false;
  }

  void _clearMetrics() {
    _avgHeartRate = 0;
    _avgSpo2 = 0;
    _heartRateTrendPercent = 0;
    _spo2TrendPercent = 0;
    _systolicBp = 0;
    _diastolicBp = 0;
    _temperature = 0;
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
}
