import 'package:equatable/equatable.dart';

enum RiskLevel { low, moderate, high, critical }

enum ImpactLevel { low, medium, high }

class HealthAnalysis extends Equatable {
  final String id;
  final String userId;
  final RiskLevel riskLevel;
  final double riskScore; // 0-100
  final String riskCategory; // e.g., "Cardiovascular", "Respiratory"
  final String summary;
  final String keyFinding;
  final List<ContributingFactor> contributingFactors;
  final List<HealthAlert> recentAlerts;
  final Map<String, dynamic> analysisData;
  final DateTime timestamp;

  const HealthAnalysis({
    required this.id,
    required this.userId,
    required this.riskLevel,
    required this.riskScore,
    required this.riskCategory,
    required this.summary,
    required this.keyFinding,
    required this.contributingFactors,
    required this.recentAlerts,
    required this.analysisData,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        riskLevel,
        riskScore,
        riskCategory,
        summary,
        keyFinding,
        contributingFactors,
        recentAlerts,
        analysisData,
        timestamp,
      ];
}

class ContributingFactor extends Equatable {
  final String id;
  final String name;
  final String description;
  final ImpactLevel impactLevel;
  final double contribution; // percentage of risk
  final String? recommendation;

  const ContributingFactor({
    required this.id,
    required this.name,
    required this.description,
    required this.impactLevel,
    required this.contribution,
    this.recommendation,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        impactLevel,
        contribution,
        recommendation,
      ];
}

class HealthAlert extends Equatable {
  final String id;
  final String userId;
  final String title;
  final String description;
  final RiskLevel severity;
  final String category; // "HR", "SpO2", "BP", "Temp"
  final DateTime timestamp;
  final bool isRead;
  final String? actionRequired;

  const HealthAlert({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.severity,
    required this.category,
    required this.timestamp,
    this.isRead = false,
    this.actionRequired,
  });

  @override
  List<Object?> get props => [
        id,
        userId,
        title,
        description,
        severity,
        category,
        timestamp,
        isRead,
        actionRequired,
      ];
}
