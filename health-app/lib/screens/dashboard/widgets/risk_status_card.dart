import 'package:flutter/material.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/models/analysis_model.dart';

class RiskStatusCard extends StatelessWidget {
  final HealthAnalysis analysis;

  const RiskStatusCard({
    Key? key,
    required this.analysis,
  }) : super(key: key);

  Color _getRiskColor() {
    switch (analysis.riskLevel) {
      case RiskLevel.low:
        return AppTheme.accentGreen;
      case RiskLevel.moderate:
        return AppTheme.accentOrange;
      case RiskLevel.high:
        return AppTheme.accentRed;
      case RiskLevel.critical:
        return AppTheme.accentRed;
    }
  }

  String _getRiskTitle() {
    switch (analysis.riskLevel) {
      case RiskLevel.low:
        return 'Low Health Risk';
      case RiskLevel.moderate:
        return 'Moderate Health Risk';
      case RiskLevel.high:
        return 'High Health Risk';
      case RiskLevel.critical:
        return 'Critical Health Risk';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getRiskColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getRiskColor().withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getRiskColor().withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    Icons.info_outline,
                    color: _getRiskColor(),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getRiskTitle(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: _getRiskColor(),
                          ),
                    ),
                    Text(
                      'Vitals are ${analysis.riskLevel.name}. Keep up the good work!',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.darkGray,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
