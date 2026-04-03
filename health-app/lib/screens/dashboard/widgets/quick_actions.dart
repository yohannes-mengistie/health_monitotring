import 'package:flutter/material.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/models/analysis_model.dart';

class QuickActionsWidget extends StatelessWidget {
  final HealthAnalysis analysis;

  const QuickActionsWidget({
    Key? key,
    required this.analysis,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth < 430
              ? (constraints.maxWidth - 12) / 2
              : (constraints.maxWidth - 24) / 3;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _buildQuickActionButton(
                      context: context,
                      icon: Icons.heart_broken,
                      label: 'Run Check',
                      onPressed: () {},
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildQuickActionButton(
                      context: context,
                      icon: Icons.play_arrow,
                      label: 'Start Session',
                      onPressed: () {},
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildQuickActionButton(
                      context: context,
                      icon: Icons.note_add,
                      label: 'Log Symptom',
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.lightGray,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: AppTheme.primaryBlue,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
