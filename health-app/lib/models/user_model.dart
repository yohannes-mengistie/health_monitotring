import 'package:equatable/equatable.dart';

enum ActivityLevel { low, moderate, high }

class User extends Equatable {
  final String id;
  final String fullName;
  final String email;
  final int age;
  final String gender; // 'male', 'female', 'other'
  final double heightCm;
  final double weightKg;
  final ActivityLevel activityLevel;
  final List<String> knownConditions;
  final List<String> currentMedications;
  final String timezone;
  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.age,
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel,
    required this.knownConditions,
    required this.currentMedications,
    required this.timezone,
    required this.createdAt,
    required this.updatedAt,
  });

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  User copyWith({
    String? id,
    String? fullName,
    String? email,
    int? age,
    String? gender,
    double? heightCm,
    double? weightKg,
    ActivityLevel? activityLevel,
    List<String>? knownConditions,
    List<String>? currentMedications,
    String? timezone,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      activityLevel: activityLevel ?? this.activityLevel,
      knownConditions: knownConditions ?? this.knownConditions,
      currentMedications: currentMedications ?? this.currentMedications,
      timezone: timezone ?? this.timezone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        fullName,
        email,
        age,
        gender,
        heightCm,
        weightKg,
        activityLevel,
        knownConditions,
        currentMedications,
        timezone,
        createdAt,
        updatedAt,
      ];
}
