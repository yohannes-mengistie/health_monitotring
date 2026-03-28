import 'package:equatable/equatable.dart';

enum PriorityLevel { low, medium, high }

enum TaskStatus { pending, inProgress, completed }

class HealthRecommendation extends Equatable {
  final String id;
  final String userId;
  final String actionPlan;
  final int totalGoals;
  final int completedGoals;
  final List<RecommendedTask> tasks;
  final List<HealthImpactProjection> expectedImpact;
  final String medicalDisclaimer;
  final DateTime createdAt;
  final DateTime updatedAt;

  const HealthRecommendation({
    required this.id,
    required this.userId,
    required this.actionPlan,
    required this.totalGoals,
    required this.completedGoals,
    required this.tasks,
    required this.expectedImpact,
    required this.medicalDisclaimer,
    required this.createdAt,
    required this.updatedAt,
  });

  int get completionPercentage =>
      totalGoals == 0 ? 0 : ((completedGoals / totalGoals) * 100).toInt();

  @override
  List<Object?> get props => [
        id,
        userId,
        actionPlan,
        totalGoals,
        completedGoals,
        tasks,
        expectedImpact,
        medicalDisclaimer,
        createdAt,
        updatedAt,
      ];
}

class RecommendedTask extends Equatable {
  final String id;
  final String title;
  final String description;
  final PriorityLevel priority;
  final TaskStatus status;
  final String category; // "Hydration", "Activity", "Sleep", "Medication"
  final DateTime? targetDate;
  final bool hasReminder;
  final String? reminderTime;
  final double? dailyTarget;
  final String? dailyUnit;
  final DateTime createdAt;

  const RecommendedTask({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.category,
    this.targetDate,
    this.hasReminder = false,
    this.reminderTime,
    this.dailyTarget,
    this.dailyUnit,
    required this.createdAt,
  });

  RecommendedTask copyWith({
    String? id,
    String? title,
    String? description,
    PriorityLevel? priority,
    TaskStatus? status,
    String? category,
    DateTime? targetDate,
    bool? hasReminder,
    String? reminderTime,
    double? dailyTarget,
    String? dailyUnit,
    DateTime? createdAt,
  }) {
    return RecommendedTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      category: category ?? this.category,
      targetDate: targetDate ?? this.targetDate,
      hasReminder: hasReminder ?? this.hasReminder,
      reminderTime: reminderTime ?? this.reminderTime,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      dailyUnit: dailyUnit ?? this.dailyUnit,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        priority,
        status,
        category,
        targetDate,
        hasReminder,
        reminderTime,
        dailyTarget,
        dailyUnit,
        createdAt,
      ];
}

class HealthImpactProjection extends Equatable {
  final String id;
  final String metric; // "HRV Recovery", "Cardio Risk Reduction"
  final double currentValue;
  final double projectedValue;
  final double percentageChange;
  final String timeframe; // "7 days", "30 days"
  final bool isPositive;

  const HealthImpactProjection({
    required this.id,
    required this.metric,
    required this.currentValue,
    required this.projectedValue,
    required this.percentageChange,
    required this.timeframe,
    required this.isPositive,
  });

  @override
  List<Object?> get props => [
        id,
        metric,
        currentValue,
        projectedValue,
        percentageChange,
        timeframe,
        isPositive,
      ];
}
