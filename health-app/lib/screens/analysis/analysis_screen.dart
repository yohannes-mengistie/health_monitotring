import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/providers/health_provider.dart';
import 'package:health_monitor_ai/models/analysis_model.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({Key? key}) : super(key: key);

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  int _currentIndex = 0;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Consumer<HealthProvider>(
        builder: (context, healthProvider, _) {
          if (healthProvider.currentAnalysis == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final analysis = healthProvider.currentAnalysis!;

          return SingleChildScrollView(
            child: Column(
              children: [
                // Navigation tabs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          _pageController?.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        'Heart Overview',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      TextButton(
                        onPressed: () {
                          _pageController?.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Heart illustration
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppTheme.lightGray,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.favorite,
                    size: 60,
                    color: AppTheme.accentRed,
                  ),
                ),
                const SizedBox(height: 24),
                // Risk overview
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              context: context,
                              icon: Icons.favorite,
                              label: 'Heart Rate',
                              value: '76',
                              unit: 'bpm',
                              status: 'Normal',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              context: context,
                              icon: Icons.warning,
                              label: 'Cardio Risk',
                              value: '22',
                              unit: '%',
                              status: 'Moderate',
                              color: AppTheme.accentOrange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              context: context,
                              icon: Icons.water_drop,
                              label: 'HRV',
                              value: '41',
                              unit: 'ms',
                              status: 'Low',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              context: context,
                              icon: Icons.water_drop,
                              label: 'SpO2',
                              value: '96',
                              unit: '%',
                              status: 'Normal',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // What Changed section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.lightGray,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppTheme.primaryBlue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'What Changed?',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          analysis.summary,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: AppTheme.primaryBlue,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  analysis.keyFinding,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Contributing Factors
                if (analysis.contributingFactors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contributing Factors',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        Column(
                          children: analysis.contributingFactors
                              .map((factor) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildFactorCard(context, factor),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                // Recent Events
                if (analysis.recentAlerts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Events',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        Column(
                          children: analysis.recentAlerts
                              .take(3)
                              .map((alert) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildEventCard(context, alert),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required String status,
    Color color = AppTheme.accentGreen,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.darkGray,
                ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              text: value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.primaryDark,
                  ),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

  Widget _buildFactorCard(BuildContext context, ContributingFactor factor) {
    Color impactColor = AppTheme.accentGreen;
    if (factor.impactLevel == ImpactLevel.high) {
      impactColor = AppTheme.accentRed;
    } else if (factor.impactLevel == ImpactLevel.medium) {
      impactColor = AppTheme.accentOrange;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.mediumGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                factor.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: impactColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${factor.impactLevel.name.toUpperCase()} IMPACT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: impactColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            factor.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.darkGray,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, HealthAlert alert) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.mediumGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                alert.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${alert.timestamp.hour}:${alert.timestamp.minute.toString().padLeft(2, '0')} ${alert.timestamp.hour >= 12 ? 'PM' : 'AM'}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.darkGray,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            alert.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.darkGray,
                ),
          ),
        ],
      ),
    );
  }
}
