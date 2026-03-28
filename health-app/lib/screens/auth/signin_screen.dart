import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/providers/auth_provider.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({Key? key}) : super(key: key);

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late TapGestureRecognizer _createAccountRecognizer;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: 'test@example.com');
    _passwordController = TextEditingController(text: 'password123');
    _createAccountRecognizer = TapGestureRecognizer()
      ..onTap = () {
        Navigator.pushNamed(context, '/signup');
      };
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _createAccountRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Welcome Back',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to access your health data and AI insights.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.darkGray,
                    ),
              ),
              const SizedBox(height: 32),
              // Social login buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.login),
                      label: const Text('Google'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.apple),
                      label: const Text('Apple'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Divider with text
              Row(
                children: [
                  Expanded(
                      child: Container(height: 1, color: AppTheme.mediumGray)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR SIGN IN WITH EMAIL',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppTheme.darkGray,
                          ),
                    ),
                  ),
                  Expanded(
                      child: Container(height: 1, color: AppTheme.mediumGray)),
                ],
              ),
              const SizedBox(height: 24),
              // Email field
              Text(
                'Email or Phone Number',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  hintText: 'Enter your email or phone',
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              // Password field
              Text(
                'Password',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Remember me & Forgot password
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() {
                            _rememberMe = value ?? false;
                          });
                        },
                      ),
                      Text(
                        'Remember me',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Forgot Password?'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Biometric login option
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fingerprint,
                      color: AppTheme.primaryBlue,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enable Biometric Login',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Use fingerprint for faster access',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: false,
                      onChanged: (value) {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Sign in button
              Consumer<AuthProvider>(
                builder: (context, authProvider, _) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: authProvider.isLoading
                          ? null
                          : () async {
                              try {
                                await authProvider.login(
                                  _emailController.text,
                                  _passwordController.text,
                                );
                                if (mounted) {
                                  Navigator.pushReplacementNamed(
                                    context,
                                    '/dashboard',
                                  );
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Sign in failed: $e')),
                                );
                              }
                            },
                      child: authProvider.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  AppTheme.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Sign up link
              Center(
                child: RichText(
                  text: TextSpan(
                    text: "Don't have an account? ",
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: [
                      TextSpan(
                        text: 'Create Account',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                        recognizer: _createAccountRecognizer,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Disclaimer
              Center(
                child: Text(
                  'By signing in, you agree to the processing of\nyour data. Check our Terms of Service and\nTelehealth/AI Limitations for details.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
