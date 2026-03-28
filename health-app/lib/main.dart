import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/providers/auth_provider.dart';
import 'package:health_monitor_ai/providers/health_provider.dart';
import 'package:health_monitor_ai/screens/auth/welcome_screen.dart';
import 'package:health_monitor_ai/screens/auth/signin_screen.dart';
import 'package:health_monitor_ai/screens/auth/signup_screen.dart';
import 'package:health_monitor_ai/screens/auth/onboarding_screen.dart';
import 'package:health_monitor_ai/screens/dashboard/dashboard_screen.dart';
import 'package:health_monitor_ai/screens/metrics/metrics_screen.dart';
import 'package:health_monitor_ai/screens/analysis/analysis_screen.dart';
import 'package:health_monitor_ai/screens/recommendations/recommendations_screen.dart';
import 'package:health_monitor_ai/screens/settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => HealthProvider()),
      ],
      child: MaterialApp(
        title: 'VitalSync - Health Monitor',
        theme: AppTheme.getLightTheme(),
        home: const SplashScreen(),
        routes: {
          '/welcome': (context) => const WelcomeScreen(),
          '/signin': (context) => const SignInScreen(),
          '/signup': (context) => const SignupScreen(),
          '/onboarding': (context) => const OnboardingScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/metrics': (context) => const MetricsScreen(),
          '/analysis': (context) => const AnalysisScreen(),
          '/recommendations': (context) => const RecommendationsScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
        navigatorObservers: [
          RouteObserver<PageRoute>(),
        ],
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    await authProvider.checkAuthStatus();

    if (mounted) {
      if (authProvider.isAuthenticated) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        Navigator.pushReplacementNamed(context, '/welcome');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primaryDark, AppTheme.primaryBlue],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Icons.favorite,
                  size: 60,
                  color: AppTheme.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'VitalSync',
                style: TextStyle(
                  color: AppTheme.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI-Powered Health Monitoring',
                style: TextStyle(
                  color: AppTheme.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppTheme.white),
                  strokeWidth: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
