import 'package:flutter/material.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/models/vitals_model.dart';

class VitalCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final VitalStatus status;

  const VitalCard({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
  }) : super(key: key);

  Color _getStatusColor() {
    switch (status) {
      case VitalStatus.normal:
        return AppTheme.accentGreen;
      case VitalStatus.elevated:
        return AppTheme.accentOrange;
      case VitalStatus.critical:
        return AppTheme.accentRed;
    }
  }

  Color _getBackgroundColor() {
    switch (status) {
      case VitalStatus.normal:
        return AppTheme.accentGreen.withOpacity(0.1);
      case VitalStatus.elevated:
        return AppTheme.accentOrange.withOpacity(0.1);
      case VitalStatus.critical:
        return AppTheme.accentRed.withOpacity(0.1);
    }
  }

  String _getStatusLabel() {
    switch (status) {
      case VitalStatus.normal:
        return 'Normal';
      case VitalStatus.elevated:
        return 'Elevated';
      case VitalStatus.critical:
        return 'Critical';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getStatusColor().withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                icon,
                color: _getStatusColor(),
                size: 24,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _getStatusLabel(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: _getStatusColor(),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.darkGray,
                ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              text: value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppTheme.primaryDark,
                  ),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
