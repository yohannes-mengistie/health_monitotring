import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  bool _didAutoRetryAfterAuth = false;
  bool _isHistoryLoading = false;
  List<Map<String, dynamic>> _historyPoints = [];
  String _historyPeriod = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOverview();
    });
  }

  Future<void> _loadOverview() async {
    final authProvider = context.read<AuthProvider>();
    var token = authProvider.authToken;

    // Handle first-open race where token may not be hydrated yet.
    if (token == null || token.isEmpty) {
      await authProvider.checkAuthStatus();
      token = authProvider.authToken;
    }

    await context.read<HealthProvider>().loadMetricsOverview(
          period: _selectedPeriod.toLowerCase(),
          token: token,
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
      body: Consumer2<AuthProvider, HealthProvider>(
        builder: (context, authProvider, healthProvider, _) {
          final data = healthProvider.metricsOverviewData;

          final token = authProvider.authToken;
          final hasToken = token != null && token.isNotEmpty;
          if (!_didAutoRetryAfterAuth &&
              hasToken &&
              !healthProvider.isLoading &&
              (data == null || data.isEmpty)) {
            _didAutoRetryAfterAuth = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _loadOverview();
            });
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
                    if (healthProvider.isLoading)
                      const LinearProgressIndicator(minHeight: 2),
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 380) {
                          return Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _exportReport(
                                      context: context,
                                      period: _selectedPeriod,
                                      scoreValue: scoreValue,
                                      scoreLabel: scoreLabel,
                                      insights: insights,
                                      summary: summary,
                                      chartPoints: chartPoints,
                                    );
                                  },
                                  icon: const Icon(Icons.download_rounded),
                                  label: const Text('Export Report'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    _showFullHistory(
                                      context: context,
                                      period: _selectedPeriod,
                                      chartPoints: chartPoints,
                                    );
                                  },
                                  icon: const Icon(Icons.history_toggle_off),
                                  label: const Text('View Full History'),
                                ),
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                    _exportReport(
                                      context: context,
                                      period: _selectedPeriod,
                                      scoreValue: scoreValue,
                                      scoreLabel: scoreLabel,
                                      insights: insights,
                                      summary: summary,
                                      chartPoints: chartPoints,
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
                                    _showFullHistory(
                                      context: context,
                                      period: _selectedPeriod,
                                      chartPoints: chartPoints,
                                    );
                                },
                                icon: const Icon(Icons.history_toggle_off),
                                label: const Text('View Full History'),
                              ),
                            ),
                          ],
                        );
                      },
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;

          final gauge = SizedBox(
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
          );

          final content = Column(
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
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                gauge,
                const SizedBox(height: 14),
                content,
              ],
            );
          }

          return Row(
            children: [
              gauge,
              const SizedBox(width: 16),
              Expanded(child: content),
            ],
          );
        },
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
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _legendDot(leftColor, leftLabel),
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

  Future<List<Map<String, dynamic>>> _fetchHistoryPoints(String period) async {
    if (_isHistoryLoading && _historyPeriod == period) return _historyPoints;

    setState(() {
      _isHistoryLoading = true;
    });

    final authProvider = context.read<AuthProvider>();
    var token = authProvider.authToken;
    if (token == null || token.isEmpty) {
      await authProvider.checkAuthStatus();
      token = authProvider.authToken;
    }

    final points = await context.read<HealthProvider>().loadMetricsHistory(
          period: period.toLowerCase(),
          token: token,
        );

    if (!mounted) return points;
    setState(() {
      _historyPoints = points;
      _historyPeriod = period;
      _isHistoryLoading = false;
    });

    return points;
  }

  Future<void> _exportReport({
    required BuildContext context,
    required String period,
    required double scoreValue,
    required String scoreLabel,
    required List<Map<String, dynamic>> insights,
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> chartPoints,
  }) async {
    final historyPoints = _historyPeriod == period
        ? _historyPoints
        : await _fetchHistoryPoints(period);
    final exportPoints =
        historyPoints.isNotEmpty ? historyPoints : chartPoints;

    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        build: (context) {
          return [
            pw.Text('Metrics Report ($period)',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Health Score: ${scoreValue.round()} ($scoreLabel)'),
            pw.SizedBox(height: 12),
            if (insights.isNotEmpty) ...[
              pw.Text('Key Insights', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              ...insights.map((item) {
                final title = item['title']?.toString() ?? 'Insight';
                final value = _toDouble(item['value']);
                final unit = item['unit']?.toString() ?? '';
                return pw.Bullet(text: '$title: ${_formatNumber(value)} $unit');
              }),
              pw.SizedBox(height: 12),
            ],
            if (summary.isNotEmpty) ...[
              pw.Text('Summary Statistics', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              ...summary.entries.map((entry) {
                final formattedKey = entry.key.replaceAll('_', ' ');
                final value = _formatNumber(_toDouble(entry.value));
                return pw.Bullet(text: '$formattedKey: $value');
              }),
              pw.SizedBox(height: 12),
            ],
            if (exportPoints.isNotEmpty) ...[
              pw.Text('History', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                headers: const ['Time', 'HR', 'SpO2', 'BP', 'Temp'],
                data: exportPoints.take(200).map((row) {
                  final label = _historyLabel(row, 0);
                  final hr = _formatNumber(_toDouble(row['"'"'heart_rate'"'"']));
                  final spo2 = _formatNumber(_toDouble(row['"'"'spo2'"'"']));
                  final bp =
                      '${_formatNumber(_toDouble(row['"'"'systolic_bp'"'"']))}/${_formatNumber(_toDouble(row['"'"'diastolic_bp'"'"']))}';
                  final temp = _formatNumber(_toDouble(row['"'"'temperature'"'"']));
                  return [label, hr, spo2, bp, temp];
                }).toList(),
              ),
            ],
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => document.save(),
      name: 'metrics_report_${period.toLowerCase()}.pdf',
    );
  }

  void _showFullHistory({
    required BuildContext context,
    required String period,
    required List<Map<String, dynamic>> chartPoints,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _historyPeriod == period
              ? Future.value(_historyPoints)
              : _fetchHistoryPoints(period),
          builder: (context, snapshot) {
            final data = snapshot.data;
            final effectivePoints =
                data != null && data.isNotEmpty ? data : chartPoints;

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Full History ($period)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (effectivePoints.isEmpty)
                      Text(
                        'No history available yet.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: effectivePoints.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = effectivePoints[index];
                            final label = _historyLabel(row, index);
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.lightGray,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'HR ${_formatNumber(_toDouble(row['"'"'heart_rate'"'"']))} bpm · SpO2 ${_formatNumber(_toDouble(row['"'"'spo2'"'"']))}% · BP ${_formatNumber(_toDouble(row['"'"'systolic_bp'"'"']))}/${_formatNumber(_toDouble(row['"'"'diastolic_bp'"'"']))} · Temp ${_formatNumber(_toDouble(row['"'"'temperature'"'"']))} C',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _historyLabel(Map<String, dynamic> row, int index) {
    final candidateKeys = ['label', 'date', 'timestamp', 'time', 'day'];
    for (final key in candidateKeys) {
      final raw = row[key];
      if (raw != null && raw.toString().trim().isNotEmpty) {
        return raw.toString();
      }
    }
    return 'Point ${index + 1}';
  }

  String _formatNumber(double value) {
    final fixed = value.truncateToDouble() == value ? 0 : 1;
    return value.toStringAsFixed(fixed);
  }
}
