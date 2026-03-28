import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/providers/auth_provider.dart';
import 'package:health_monitor_ai/providers/health_provider.dart';
import 'package:health_monitor_ai/screens/dashboard/widgets/vital_card.dart';
import 'package:health_monitor_ai/screens/dashboard/widgets/risk_status_card.dart';
import 'package:health_monitor_ai/screens/dashboard/widgets/quick_actions.dart';
import 'package:health_monitor_ai/screens/dashboard/widgets/recent_alerts.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  Timer? _pollTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHealth();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      _initializeHealth();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializeHealth() async {
    if (_isRefreshing) return;

    final authProvider = context.read<AuthProvider>();
    final healthProvider = context.read<HealthProvider>();

    if (authProvider.currentUser != null) {
      _isRefreshing = true;
      try {
        await healthProvider.loadLiveVitalsAndRisk(
          userId: authProvider.currentUser!.id,
          token: authProvider.authToken,
          showLoading: healthProvider.currentVitals == null,
        );
      } finally {
        _isRefreshing = false;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final authProvider = context.read<AuthProvider>();
      final healthProvider = context.read<HealthProvider>();

      if (authProvider.currentUser != null) {
        healthProvider.loadLiveVitalsAndRisk(
          userId: authProvider.currentUser!.id,
          token: authProvider.authToken,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _buildContent(),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildContent() {
    return Consumer2<AuthProvider, HealthProvider>(
      builder: (context, authProvider, healthProvider, _) {
        if (healthProvider.isLoading) {
          if (healthProvider.currentVitals != null) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  const LinearProgressIndicator(minHeight: 2),
                  _buildDashboardBody(authProvider, healthProvider),
                ],
              ),
            );
          }

          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        return _buildDashboardBody(authProvider, healthProvider);
      },
    );
  }

  Widget _buildDashboardBody(
    AuthProvider authProvider,
    HealthProvider healthProvider,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello,',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        Text(
                          authProvider.currentUser?.fullName ?? 'User',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                      ],
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.lightGray,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Center(
                            child: Text(
                              authProvider.currentUser?.fullName
                                      .substring(0, 1)
                                      .toUpperCase() ??
                                  '?',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(
                                    color: AppTheme.primaryBlue,
                                  ),
                            ),
                          ),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppTheme.accentGreen,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.white,
                                width: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Device sync status
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.devices_other,
                        color: AppTheme.primaryBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BioBand Pro',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: AppTheme.primaryBlue,
                                  ),
                            ),
                            Text(
                              'Connected • 84% Battery',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        child: const Text(
                          'Sync Now',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Risk status card
          if (healthProvider.currentAnalysis != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: RiskStatusCard(
                analysis: healthProvider.currentAnalysis!,
              ),
            ),
          const SizedBox(height: 24),
          // Live Vitals section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Live Vitals',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      'Updated just now',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.darkGray,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          // Vitals grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                if (healthProvider.currentVitals != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: VitalCard(
                          icon: Icons.favorite,
                          label: 'Heart Rate',
                          value: healthProvider.currentVitals!.heartRate
                              .toString(),
                          unit: 'bpm',
                          status: healthProvider.currentVitals!
                              .getHeartRateStatus(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: VitalCard(
                          icon: Icons.water_drop,
                          label: 'SpO2',
                          value: healthProvider.currentVitals!.spo2
                              .toStringAsFixed(1),
                          unit: '%',
                          status: healthProvider.currentVitals!.getSpo2Status(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: VitalCard(
                          icon: Icons.favorite_border,
                          label: 'Blood Pressure',
                          value:
                              '${healthProvider.currentVitals!.systolicBP}/${healthProvider.currentVitals!.diastolicBP}',
                          unit: 'mmHg',
                          status: healthProvider.currentVitals!.getBPStatus(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: VitalCard(
                          icon: Icons.thermostat,
                          label: 'Temperature',
                          value: healthProvider.currentVitals!.temperature
                              .toStringAsFixed(1),
                          unit: '°C',
                          status: healthProvider.currentVitals!
                              .getTemperatureStatus(),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.lightGray,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.mediumGray),
                    ),
                    child: Text(
                      healthProvider.errorMessage ??
                          'No live vitals yet. Keep the serial listener running and streaming sensor data.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Quick Actions
          if (healthProvider.currentAnalysis != null)
            QuickActionsWidget(
              analysis: healthProvider.currentAnalysis!,
            ),
          const SizedBox(height: 24),
          // Recent Alerts
          if (healthProvider.currentAnalysis != null)
            RecentAlertsWidget(
              alerts: healthProvider.currentAnalysis!.recentAlerts,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(
            color: AppTheme.darkGray.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Metrics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Analysis',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb_outline),
            label: 'Tips',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });

          switch (index) {
            case 0:
              // Home - stay here
              break;
            case 1:
              Navigator.pushNamed(context, '/metrics');
              break;
            case 2:
              Navigator.pushNamed(context, '/analysis');
              break;
            case 3:
              Navigator.pushNamed(context, '/recommendations');
              break;
            case 4:
              Navigator.pushNamed(context, '/settings');
              break;
          }
        },
      ),
    );
  }
}
