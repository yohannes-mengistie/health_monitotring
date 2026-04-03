import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/models/analysis_model.dart';

class RecentAlertsWidget extends StatelessWidget {
  final List<HealthAlert> alerts;

  const RecentAlertsWidget({
    Key? key,
    required this.alerts,
  }) : super(key: key);

  Color _getSeverityColor(RiskLevel severity) {
    switch (severity) {
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

  IconData _getSeverityIcon(RiskLevel severity) {
    switch (severity) {
      case RiskLevel.low:
        return Icons.check_circle;
      case RiskLevel.moderate:
        return Icons.warning;
      case RiskLevel.high:
        return Icons.error;
      case RiskLevel.critical:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Alerts',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {},
                        child: const Text('View All'),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Recent Alerts',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('View All'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Column(
            children: alerts.take(3).map((alert) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildAlertItem(context, alert),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertItem(BuildContext context, HealthAlert alert) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getSeverityColor(alert.severity).withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getSeverityColor(alert.severity).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(
                _getSeverityIcon(alert.severity),
                color: _getSeverityColor(alert.severity),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  alert.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM dd, hh:mm a').format(alert.timestamp),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                ),
              ],
            ),
          ),
          if (alert.actionRequired != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: _getSeverityColor(alert.severity).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Action',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _getSeverityColor(alert.severity),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
