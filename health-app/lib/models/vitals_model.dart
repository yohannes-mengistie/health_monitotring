import 'package:equatable/equatable.dart';

enum VitalStatus { normal, elevated, critical }

class VitalReading extends Equatable {
  final String id;
  final String userId;
  final int heartRate; // bpm
  final double spo2; // %
  final int systolicBP; // mmHg
  final int diastolicBP; // mmHg
  final double temperature; // Celsius
  final DateTime timestamp;
  final String deviceName;

  const VitalReading({
    required this.id,
    required this.userId,
    required this.heartRate,
    required this.spo2,
    required this.systolicBP,
    required this.diastolicBP,
    required this.temperature,
    required this.timestamp,
    this.deviceName = 'Mobile Sensor',
  });

  VitalStatus getHeartRateStatus() {
    if (heartRate < 60 || heartRate > 100) return VitalStatus.elevated;
    if (heartRate < 40 || heartRate > 120) return VitalStatus.critical;
    return VitalStatus.normal;
  }

  VitalStatus getSpo2Status() {
    if (spo2 < 95) return VitalStatus.critical;
    if (spo2 < 98) return VitalStatus.elevated;
    return VitalStatus.normal;
  }

  VitalStatus getBPStatus() {
    if (systolicBP >= 140 || diastolicBP >= 90) {
      return VitalStatus.critical;
    }
    if (systolicBP >= 130 || diastolicBP >= 80) {
      return VitalStatus.elevated;
    }
    return VitalStatus.normal;
  }

  VitalStatus getTemperatureStatus() {
    if (temperature < 36.1 || temperature > 37.2) {
      return VitalStatus.elevated;
    }
    if (temperature < 35 || temperature > 38.5) {
      return VitalStatus.critical;
    }
    return VitalStatus.normal;
  }

  VitalStatus getOverallStatus() {
    final statuses = [
      getHeartRateStatus(),
      getSpo2Status(),
      getBPStatus(),
      getTemperatureStatus(),
    ];

    if (statuses.contains(VitalStatus.critical)) {
      return VitalStatus.critical;
    }
    if (statuses.contains(VitalStatus.elevated)) {
      return VitalStatus.elevated;
    }
    return VitalStatus.normal;
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        heartRate,
        spo2,
        systolicBP,
        diastolicBP,
        temperature,
        timestamp,
        deviceName,
      ];
}

class VitalsTrend extends Equatable {
  final List<VitalReading> readings;
  final DateTime startDate;
  final DateTime endDate;

  const VitalsTrend({
    required this.readings,
    required this.startDate,
    required this.endDate,
  });

  double get averageHeartRate =>
      readings.isEmpty
          ? 0
          : readings.map((e) => e.heartRate).reduce((a, b) => a + b) /
              readings.length;

  double get averageSpo2 =>
      readings.isEmpty
          ? 0
          : readings.map((e) => e.spo2).reduce((a, b) => a + b) /
              readings.length;

  double get averageTemperature =>
      readings.isEmpty
          ? 0
          : readings.map((e) => e.temperature).reduce((a, b) => a + b) /
              readings.length;

  @override
  List<Object?> get props => [readings, startDate, endDate];
}
