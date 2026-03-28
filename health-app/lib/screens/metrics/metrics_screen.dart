import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:health_monitor_ai/providers/auth_provider.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/providers/health_provider.dart';

class MetricsScreen extends StatefulWidget {
  const MetricsScreen({Key? key}) : super(key: key);

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  String _selectedPeriod = 'Week';
  final List<String> _periods = ['Day', 'Week', 'Month', 'Year'];
  final List<String> _metrics = ['All', 'Cardiovascular', 'Respiratory'];
  String _selectedMetric = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOverview();
    });
  }

  Future<void> _loadOverview() async {
    final authProvider = context.read<AuthProvider>();
    await context.read<HealthProvider>().loadMetricsOverview(
          period: _selectedPeriod.toLowerCase(),
          token: authProvider.authToken,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metrics Overview'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search
            TextField(
              decoration: InputDecoration(
                hintText: 'Search metrics...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppTheme.lightGray,
              ),
            ),
            const SizedBox(height: 24),
            // Metric type filters
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _metrics.map((metric) {
                  final isSelected = _selectedMetric == metric;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(metric),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedMetric = metric;
                        });
                      },
                      backgroundColor: AppTheme.lightGray,
                      selectedColor: AppTheme.primaryBlue,
                      labelStyle: TextStyle(
                        color: isSelected ? AppTheme.white : AppTheme.darkGray,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            // Time period selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _periods.map((period) {
                final isSelected = _selectedPeriod == period;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPeriod = period;
                    });
                    _loadOverview();
                  },
                  child: Column(
                    children: [
                      Text(
                        period,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isSelected
                                  ? AppTheme.primaryBlue
                                  : AppTheme.darkGray,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                      ),
                      if (isSelected)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          height: 3,
                          width: 20,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            // Pinned Metrics section
            Text(
              'PINNED METRICS',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppTheme.darkGray,
                  ),
            ),
            Consumer<HealthProvider>(
              builder: (context, healthProvider, _) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    healthProvider.metricsUsingBackend
                        ? 'Source: Backend API'
                        : 'Source: Mock fallback',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                  ),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(),
                TextButton(
                  onPressed: () {},
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Consumer<HealthProvider>(
              builder: (context, healthProvider, _) {
                if (healthProvider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                return Column(
                  children: [
                    // Average Heart Rate
                    _buildMetricCard(
                      context: context,
                      icon: Icons.favorite,
                      label: 'Average Heart Rate',
                      value: healthProvider.avgHeartRate.toStringAsFixed(1),
                      unit: 'bpm',
                      change:
                          _formatPercent(healthProvider.heartRateTrendPercent),
                      lastValue: '${_selectedPeriod.toLowerCase()}: baseline',
                      showChart: true,
                    ),
                    const SizedBox(height: 16),
                    // Average SpO2
                    _buildMetricCard(
                      context: context,
                      icon: Icons.water_drop,
                      label: 'Average SpO2',
                      value: healthProvider.avgSpo2.toStringAsFixed(1),
                      unit: '%',
                      change: _formatPercent(healthProvider.spo2TrendPercent),
                      lastValue: '${_selectedPeriod.toLowerCase()}: baseline',
                      showChart: true,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            // Other metrics
            Text(
              'OTHER METRICS',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppTheme.darkGray,
                  ),
            ),
            const SizedBox(height: 12),
            Consumer<HealthProvider>(
              builder: (context, healthProvider, _) {
                if (healthProvider.isLoading) {
                  return const SizedBox.shrink();
                }

                return Column(
                  children: [
                    _buildSimpleMetricCard(
                      context: context,
                      label: 'Blood Pressure',
                      value:
                          '${healthProvider.systolicBp}/${healthProvider.diastolicBp} mmHg',
                      icon: Icons.favorite_border,
                    ),
                    const SizedBox(height: 8),
                    _buildSimpleMetricCard(
                      context: context,
                      label: 'Temperature',
                      value:
                          '${healthProvider.temperature.toStringAsFixed(1)}°C',
                      icon: Icons.thermostat,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatPercent(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)}%';
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required String change,
    required String lastValue,
    required bool showChart,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(icon, color: AppTheme.primaryBlue),
              IconButton(
                icon: const Icon(Icons.star_border),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              text: value,
              style: Theme.of(context).textTheme.displayMedium,
              children: [
                TextSpan(
                  text: ' $unit',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  change,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.accentGreen,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'last week: $lastValue',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.darkGray,
                    ),
              ),
            ],
          ),
          if (showChart) ...[
            const SizedBox(height: 16),
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.lightGray,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Chart visualization here',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimpleMetricCard({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.lightGray,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryBlue),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                  ),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ],
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
