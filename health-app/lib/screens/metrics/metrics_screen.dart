import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
        title: const Text('Metrics & Insights'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<HealthProvider>(
        builder: (context, healthProvider, _) {
          final data = healthProvider.metricsOverviewData;

          if (healthProvider.isLoading && (data == null || data.isEmpty)) {
            return const Center(child: CircularProgressIndicator());
          }

          if (data == null || data.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  healthProvider.errorMessage ??
                      'No metrics available yet. Complete a few measurement cycles first.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final score = _asMap(data['health_score']);
          final scoreValue = _toDouble(score['value']).clamp(0, 100).toDouble();
          final scoreLabel = score['label']?.toString() ?? 'Health Status';

          final insights = _asMapList(data['insights']);
          final chartPoints = _asMapList(data['chart_points']);
          final summary = _asMap(data['summary_statistics']);

          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: _loadOverview,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildPeriodSelector(),
                    const SizedBox(height: 18),
                    _buildScoreCard(scoreValue, scoreLabel),
                    const SizedBox(height: 18),
                    _buildInsightsSection(insights),
                    const SizedBox(height: 18),
                    _buildChartSection(
                      title: 'Heart Rate Trend',
                      color: AppTheme.accentRed,
                      points: _spots(chartPoints, 'heart_rate'),
                      unit: 'bpm',
                    ),
                    const SizedBox(height: 14),
                    _buildChartSection(
                      title: 'SpO2 Trend',
                      color: AppTheme.primaryBlue,
                      points: _spots(chartPoints, 'spo2'),
                      unit: '%',
                    ),
                    const SizedBox(height: 14),
                    _buildDualChartSection(
                      title: 'Blood Pressure Trend',
                      leftLabel: 'Systolic',
                      rightLabel: 'Diastolic',
                      leftColor: AppTheme.accentOrange,
                      rightColor: AppTheme.accentPurple,
                      leftPoints: _spots(chartPoints, 'systolic_bp'),
                      rightPoints: _spots(chartPoints, 'diastolic_bp'),
                    ),
                    const SizedBox(height: 14),
                    _buildChartSection(
                      title: 'Temperature Trend',
                      color: AppTheme.accentGreen,
                      points: _spots(chartPoints, 'temperature'),
                      unit: 'C',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Summary Statistics',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    _buildSummaryGrid(summary),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Export will be available in the next update.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Export Report'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Full history view will be added next.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.history_toggle_off),
                            label: const Text('View Full History'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              if (healthProvider.isLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.mediumGray),
      ),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: _periods
            .map(
              (period) => ButtonSegment<String>(
                value: period,
                label: Text(period),
              ),
            )
            .toList(),
        selected: <String>{_selectedPeriod},
        onSelectionChanged: (selected) {
          final newPeriod = selected.first;
          if (newPeriod == _selectedPeriod) return;
          setState(() {
            _selectedPeriod = newPeriod;
          });
          _loadOverview();
        },
      ),
    );
  }

  Widget _buildScoreCard(double score, String label) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryBlue,
            AppTheme.primaryBlue.withOpacity(0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            height: 96,
            width: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 9,
                  backgroundColor: AppTheme.white.withOpacity(0.18),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppTheme.white),
                ),
                Text(
                  '${score.round()}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppTheme.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Health Score',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.white.withOpacity(0.92),
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$label • $_selectedPeriod',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Trend-focused view for stable clinical interpretation.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.white.withOpacity(0.82),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsSection(List<Map<String, dynamic>> insights) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key Insights',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 155,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: insights.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = insights[index];
              final value = _toDouble(item['value']);
              final unit = item['unit']?.toString() ?? '';
              return Container(
                width: 230,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.mediumGray),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title']?.toString() ?? 'Insight',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)} $unit',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item['description']?.toString() ?? '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChartSection({
    required String title,
    required Color color,
    required List<FlSpot> points,
    required String unit,
  }) {
    final hasPoints = points.isNotEmpty;
    final chartPoints = hasPoints ? points : [const FlSpot(0, 0)];
    final minY = _minY(chartPoints);
    final maxY = _maxY(chartPoints);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.mediumGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: chartPoints.length > 1
                    ? (chartPoints.length - 1).toDouble()
                    : 1,
                minY: minY,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  horizontalInterval:
                      (maxY - minY) <= 0 ? 1 : (maxY - minY) / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.mediumGray,
                    strokeWidth: 1,
                  ),
                  drawVerticalLine: false,
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, _) => Text(
                        '${value.toStringAsFixed(0)}$unit',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineTouchData: LineTouchData(enabled: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: chartPoints,
                    color: color,
                    barWidth: 3,
                    isCurved: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!hasPoints)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No chart samples available in this period yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDualChartSection({
    required String title,
    required String leftLabel,
    required String rightLabel,
    required Color leftColor,
    required Color rightColor,
    required List<FlSpot> leftPoints,
    required List<FlSpot> rightPoints,
  }) {
    final merged = [...leftPoints, ...rightPoints];
    final hasPoints = merged.isNotEmpty;
    final renderLeft =
        leftPoints.isNotEmpty ? leftPoints : [const FlSpot(0, 0)];
    final renderRight =
        rightPoints.isNotEmpty ? rightPoints : [const FlSpot(0, 0)];
    final chartPoints =
        hasPoints ? merged : [const FlSpot(0, 0), const FlSpot(1, 1)];
    final minY = _minY(chartPoints);
    final maxY = _maxY(chartPoints);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.mediumGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              _legendDot(leftColor, leftLabel),
              const SizedBox(width: 10),
              _legendDot(rightColor, rightLabel),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: chartPoints.length > 1
                    ? (chartPoints.length - 1).toDouble()
                    : 1,
                minY: minY,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  horizontalInterval:
                      (maxY - minY) <= 0 ? 1 : (maxY - minY) / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.mediumGray,
                    strokeWidth: 1,
                  ),
                  drawVerticalLine: false,
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (value, _) => Text(
                        value.toStringAsFixed(0),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: renderLeft,
                    color: leftColor,
                    barWidth: 3,
                    isCurved: true,
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: renderRight,
                    color: rightColor,
                    barWidth: 3,
                    isCurved: true,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          if (!hasPoints)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No blood pressure samples available in this period yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildSummaryGrid(Map<String, dynamic> summary) {
    final metricCards = <Widget>[];
    final entries = [
      ['Heart Rate', _asMap(summary['heart_rate'])],
      ['SpO2', _asMap(summary['spo2'])],
      ['Temperature', _asMap(summary['temperature'])],
      ['Systolic BP', _asMap(summary['systolic_bp'])],
      ['Diastolic BP', _asMap(summary['diastolic_bp'])],
    ];

    for (final entry in entries) {
      final label = entry[0] as String;
      final data = entry[1] as Map<String, dynamic>;
      if (data.isEmpty) continue;
      final unit = data['unit']?.toString() ?? '';
      metricCards.add(
        Container(
          width: 250,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.mediumGray),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _statRow('Avg', data['avg'], unit),
              _statRow('Min', data['min'], unit),
              _statRow('Max', data['max'], unit),
              _statRow('Std Dev', data['std_dev'], unit),
            ],
          ),
        ),
      );
    }

    if (metricCards.isEmpty) {
      return Text(
        'No summary statistics available yet.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: metricCards,
    );
  }

  Widget _statRow(String label, dynamic value, String unit) {
    final asDouble = _toDouble(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            '${asDouble.toStringAsFixed(2)} $unit',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }

  List<FlSpot> _spots(List<Map<String, dynamic>> rows, String key) {
    final spots = <FlSpot>[];
    for (var i = 0; i < rows.length; i++) {
      spots.add(FlSpot(i.toDouble(), _toDouble(rows[i][key])));
    }
    return spots;
  }

  double _minY(List<FlSpot> points) {
    var min = points.first.y;
    for (final point in points) {
      if (point.y < min) min = point.y;
    }
    return min - (min.abs() * 0.08) - 1;
  }

  double _maxY(List<FlSpot> points) {
    var max = points.first.y;
    for (final point in points) {
      if (point.y > max) max = point.y;
    }
    return max + (max.abs() * 0.08) + 1;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((entry) => entry.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
