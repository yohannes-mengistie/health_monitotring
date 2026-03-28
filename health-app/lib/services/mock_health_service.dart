import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:health_monitor_ai/models/user_model.dart';
import 'package:health_monitor_ai/models/vitals_model.dart';
import 'package:health_monitor_ai/models/analysis_model.dart';
import 'package:health_monitor_ai/models/recommendation_model.dart';

class MockHealthService {
  static const _uuid = Uuid();
  static final Random _random = Random();

  // Mock user data
  static User generateMockUser({
    String? id,
    String? fullName,
    String? email,
  }) {
    return User(
      id: id ?? _uuid.v4(),
      fullName: fullName ?? 'Abraham Smith',
      email: email ?? 'abraham.smith@example.com',
      age: 35,
      gender: 'male',
      heightCm: 180,
      weightKg: 78,
      activityLevel: ActivityLevel.moderate,
      knownConditions: ['Hypertension'],
      currentMedications: ['Lisinopril 10mg'],
      timezone: 'Eastern Time (ET)',
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      updatedAt: DateTime.now(),
    );
  }

  // Generate realistic vital readings based on time patterns
  static VitalReading generateMockVitalReading({
    required String userId,
    DateTime? timestamp,
  }) {
    timestamp ??= DateTime.now();
    final hour = timestamp.hour;

    // Simulate circadian rhythm variations
    double hrVariation = 1.0;
    double bpVariation = 1.0;

    if (hour >= 22 || hour < 6) {
      // Night: lower HR, lower BP
      hrVariation = 0.85;
      bpVariation = 0.9;
    } else if (hour >= 8 && hour < 10) {
      // Morning peak
      hrVariation = 1.1;
      bpVariation = 1.05;
    }

    final baseHR = 72;
    final baseSystolic = 128;
    final baseDiastolic = 82;

    return VitalReading(
      id: _uuid.v4(),
      userId: userId,
      heartRate: (baseHR * hrVariation).toInt() + _random.nextInt(15) - 7,
      spo2: 96.0 + _random.nextDouble() * 2,
      systolicBP:
          (baseSystolic * bpVariation).toInt() + _random.nextInt(10) - 5,
      diastolicBP:
          (baseDiastolic * bpVariation).toInt() + _random.nextInt(8) - 4,
      temperature: 36.8 + (_random.nextDouble() - 0.5) * 0.5,
      timestamp: timestamp,
    );
  }

  // Generate mock vitals history for trend analysis
  static List<VitalReading> generateMockVitalsHistory({
    required String userId,
    required int days,
  }) {
    final readings = <VitalReading>[];
    final now = DateTime.now();

    for (int d = days; d >= 0; d--) {
      for (int h = 0; h < 24; h += 4) {
        final timestamp = now.subtract(Duration(days: d, hours: h));
        readings.add(generateMockVitalReading(
          userId: userId,
          timestamp: timestamp,
        ));
      }
    }

    return readings;
  }

  // Generate health analysis based on vitals
  static HealthAnalysis generateMockAnalysis({
    required String userId,
    required List<VitalReading> recentReadings,
  }) {
    if (recentReadings.isEmpty) {
      return _generateDefaultAnalysis(userId);
    }

    final avgHR =
        recentReadings.map((e) => e.heartRate).reduce((a, b) => a + b) /
            recentReadings.length;
    final avgBP =
        recentReadings.map((e) => e.systolicBP).reduce((a, b) => a + b) /
            recentReadings.length;

    // Calculate risk score based on vitals
    double riskScore = 20; // baseline
    RiskLevel riskLevel = RiskLevel.low;

    if (avgBP > 140) {
      riskScore += 30;
      riskLevel = RiskLevel.high;
    } else if (avgBP > 130) {
      riskScore += 15;
      riskLevel = RiskLevel.moderate;
    }

    if (avgHR > 100) {
      riskScore += 20;
      if (riskLevel == RiskLevel.low) riskLevel = RiskLevel.moderate;
    }

    final contributingFactors = <ContributingFactor>[
      ContributingFactor(
        id: _uuid.v4(),
        name: 'HRV Variability',
        description: 'Dropped below 45ms threshold',
        impactLevel: ImpactLevel.high,
        contribution: 35,
        recommendation: 'Focus on stress reduction techniques',
      ),
      ContributingFactor(
        id: _uuid.v4(),
        name: 'Sleep Quality',
        description: '-1.3 hrs avg over 3 days',
        impactLevel: ImpactLevel.medium,
        contribution: 25,
        recommendation: 'Maintain consistent sleep schedule',
      ),
      ContributingFactor(
        id: _uuid.v4(),
        name: 'Physical Activity',
        description: 'Below recommended levels',
        impactLevel: ImpactLevel.medium,
        contribution: 20,
        recommendation: 'Increase daily movement',
      ),
    ];

    final recentAlerts = <HealthAlert>[
      HealthAlert(
        id: _uuid.v4(),
        userId: userId,
        title: 'HRV Alert Triggered',
        description: 'Morning heart rate variability score dropped to 32/100.',
        severity: RiskLevel.high,
        category: 'HRV',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        actionRequired: 'Take an ECG measurement',
      ),
      HealthAlert(
        id: _uuid.v4(),
        userId: userId,
        title: 'Poor Sleep Detected',
        description: 'Frequent awakenings and low sleep quality.',
        severity: RiskLevel.moderate,
        category: 'Sleep',
        timestamp: DateTime.now().subtract(const Duration(hours: 8)),
        actionRequired: 'Review sleep optimization tips',
      ),
    ];

    return HealthAnalysis(
      id: _uuid.v4(),
      userId: userId,
      riskLevel: riskLevel,
      riskScore: riskScore.clamp(0, 100),
      riskCategory: 'Cardiovascular',
      summary:
          'Your cardiovascular risk score increased by 4% over the last 72 hours. This is primarily driven by a sustained decrease in Heart Rate Variability (HRV) during sleep periods.',
      keyFinding:
          'Heart rate variability (HRV) pattern is often associated with elevated stress or incomplete recovery.',
      contributingFactors: contributingFactors,
      recentAlerts: recentAlerts,
      analysisData: {
        'hrv_trend': 'declining',
        'sleep_efficiency': 0.72,
        'stress_level': 'elevated',
        'recovery_score': 58,
      },
      timestamp: DateTime.now(),
    );
  }

  static HealthAnalysis _generateDefaultAnalysis(String userId) {
    return HealthAnalysis(
      id: _uuid.v4(),
      userId: userId,
      riskLevel: RiskLevel.low,
      riskScore: 22,
      riskCategory: 'Cardiovascular',
      summary: 'Your vitals are stable. Keep up the good work!',
      keyFinding: 'All metrics are within normal ranges.',
      contributingFactors: [],
      recentAlerts: [],
      analysisData: {},
      timestamp: DateTime.now(),
    );
  }

  // Generate AI-powered recommendations
  static HealthRecommendation generateMockRecommendations({
    required String userId,
    required HealthAnalysis analysis,
  }) {
    final tasks = <RecommendedTask>[
      RecommendedTask(
        id: _uuid.v4(),
        title: 'Hydration Goal',
        description:
            'Drink 2.5L of water today to support cardiovascular function',
        priority: PriorityLevel.high,
        status: TaskStatus.pending,
        category: 'Hydration',
        dailyTarget: 2.5,
        dailyUnit: 'L',
        hasReminder: true,
        reminderTime: '09:00',
        createdAt: DateTime.now(),
      ),
      RecommendedTask(
        id: _uuid.v4(),
        title: 'Light Activity',
        description:
            '20-min light walk, avoid intense exercise due to elevated HRV',
        priority: PriorityLevel.medium,
        status: TaskStatus.pending,
        category: 'Activity',
        dailyTarget: 20,
        dailyUnit: 'min',
        hasReminder: true,
        reminderTime: '14:00',
        createdAt: DateTime.now(),
      ),
      RecommendedTask(
        id: _uuid.v4(),
        title: 'Sleep Optimization',
        description: 'Target 8h sleep. No screens 1h before bed',
        priority: PriorityLevel.high,
        status: TaskStatus.pending,
        category: 'Sleep',
        targetDate: DateTime.now().add(const Duration(days: 1)),
        hasReminder: true,
        reminderTime: '21:00',
        createdAt: DateTime.now(),
      ),
      RecommendedTask(
        id: _uuid.v4(),
        title: 'Morning Check-in',
        description: 'Log morning symptoms and energy level',
        priority: PriorityLevel.medium,
        status: TaskStatus.completed,
        category: 'Monitoring',
        hasReminder: true,
        reminderTime: '08:00',
        createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      ),
    ];

    final impacts = <HealthImpactProjection>[
      HealthImpactProjection(
        id: _uuid.v4(),
        metric: 'HRV Recovery',
        currentValue: 32,
        projectedValue: 52,
        percentageChange: 15,
        timeframe: '7 days',
        isPositive: true,
      ),
      HealthImpactProjection(
        id: _uuid.v4(),
        metric: 'Cardio Risk Reduction',
        currentValue: 22,
        projectedValue: 18,
        percentageChange: -8,
        timeframe: '30 days',
        isPositive: true,
      ),
    ];

    return HealthRecommendation(
      id: _uuid.v4(),
      userId: userId,
      actionPlan: '''### 🩺 Clinical Assessment
    Your vital-sign profile is generally reassuring. Oxygen saturation, temperature, and heart rate are stable, while a mild elevation in blood pressure should be monitored. Overall, your model output indicates LOW RISK.

    ### 🎯 Key Focus Areas
    * **Derived_BMI (21.74) -> drove risk UP**: The model flagged this as upward pressure, though clinically this remains a healthy BMI range.
    * **Heart Rate (64) -> drove risk UP**: The model contribution is positive in its internal logic, but a resting heart rate in this range is usually favorable.
    * **Age (65) -> kept risk DOWN**: The model considered your broader profile protective for your age context.

    ### 📋 Action Plan
    1. **Blood Pressure Support**: Reduce sodium intake and increase potassium-rich foods.
    2. **Cardio Fitness Maintenance**: Keep a weekly routine of moderate aerobic activity.
    3. **Follow-up Review**: Recheck blood pressure trends with your clinician in 3-6 months.

    *Disclaimer: This is an AI-generated clinical triage summary. Please consult a licensed healthcare professional for diagnosis.*

    --------------------------------------------------

    ### 🩺 ክሊኒካዊ ግምገማ
    አጠቃላይ የጤና መለኪያዎችዎ በጥሩ ሁኔታ ላይ ናቸው። አንዳንድ የደም ግፊት መለኪያዎች ትንሽ ከፍ ቢሉም አጠቃላይ ሁኔታዎ ዝቅተኛ ስጋት ያሳያል።

    ### 🎯 ዋና ትኩረት የሚሹ ጉዳዮች
    * **BMI (22.42)**: በጤናማ ክልል ውስጥ ይገኛል።
    * **የልብ ምት (74)**: መደበኛ እና ጤናማ ነው።
    * **ዕድሜ (49)**: በመደበኛ ክትትል ጤና መጠበቅ ይቻላል።

    ### 📋 የተግባር እቅድ
    1. **የተመጣጠነ ምግብ**: ጨው ዝቅ አድርጉ እና አትክልት ይጨምሩ።
    2. **የአካል እንቅስቃሴ**: በሳምንት 150 ደቂቃ መጠነኛ እንቅስቃሴ ያድርጉ።
    3. **መደበኛ ምርመራ**: ከህክምና ባለሙያ ጋር ቀጣይ ቆይታ ያድርጉ።

    *ማሳሰቢያ: ይህ በ AI የተዘጋጀ የመጀመሪያ ደረጃ ግምገማ ነው። ለትክክለኛ ምርመራ የጤና ባለሙያን ያማክሩ።*''',
      totalGoals: tasks.length,
      completedGoals:
          tasks.where((t) => t.status == TaskStatus.completed).length,
      tasks: tasks,
      expectedImpact: impacts,
      medicalDisclaimer:
          'These AI-generated recommendations are for informational purposes only and do not replace professional medical advice. If you experience chest pain or severe shortness of breath, contact emergency services immediately.',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // Generate mock settings/device data
  static Map<String, dynamic> generateMockDevices() {
    return {
      'devices': [
        {
          'id': 'watch_1',
          'name': 'HealthWatch Pro',
          'type': 'Smartwatch',
          'status': 'Connected',
          'battery': 84,
          'lastSync': DateTime.now().subtract(const Duration(minutes: 5)),
        },
        {
          'id': 'ring_1',
          'name': 'Oura Ring Gen3',
          'type': 'Ring',
          'status': 'Not Connected',
          'battery': null,
          'lastSync': DateTime.now().subtract(const Duration(days: 2)),
        },
      ],
    };
  }

  // Generate alert thresholds
  static Map<String, dynamic> generateMockAlertThresholds() {
    return {
      'heartRate': {'min': 40, 'max': 100, 'enabled': true},
      'temperature': {'min': 36.1, 'max': 37.2, 'enabled': true},
      'spo2': {'min': 95, 'max': 100, 'enabled': true},
      'systolicBP': {'max': 140, 'enabled': true},
      'diastolicBP': {'max': 90, 'enabled': true},
    };
  }
}
