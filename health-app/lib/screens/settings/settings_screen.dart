import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  bool _emailSummaries = false;
  bool _heartRateAlerts = true;
  bool _temperatureAlerts = true;
  bool _spo2Alerts = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Section
            Consumer<AuthProvider>(
              builder: (context, authProvider, _) {
                final user = authProvider.currentUser;
                if (user == null) {
                  return const SizedBox.shrink();
                }

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.mediumGray),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppTheme.lightGray,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                user.fullName.substring(0, 1).toUpperCase(),
                                style:
                                    Theme.of(context).textTheme.displayMedium,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.fullName,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  user.email,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.verified,
                              color: AppTheme.accentGreen),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _showEditProfileDialog(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                          ),
                          child: const Text('Edit Profile'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            // Devices & Sensors
            _buildSectionTitle(context, 'DEVICES & SENSORS'),
            const SizedBox(height: 12),
            _buildSettingsItem(
              context: context,
              icon: Icons.devices_other,
              title: 'HealthWatch Pro',
              subtitle: 'Connected • Battery 84%',
              trailing: const Icon(Icons.chevron_right),
            ),
            const SizedBox(height: 8),
            _buildSettingsItem(
              context: context,
              icon: Icons.ring_volume,
              title: 'Oura Ring Gen3',
              subtitle: 'Not Connected',
              trailing: const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Pair',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Alerts & Thresholds
            _buildSectionTitle(context, 'ALERTS & THRESHOLDS'),
            const SizedBox(height: 12),
            _buildToggleItem(
              context: context,
              icon: Icons.favorite,
              title: 'Heart Rate Alerts',
              subtitle: 'Notify if ≥ 120 bpm resting',
              value: _heartRateAlerts,
              onChanged: (value) {
                setState(() {
                  _heartRateAlerts = value;
                });
              },
            ),
            const SizedBox(height: 8),
            _buildToggleItem(
              context: context,
              icon: Icons.thermostat,
              title: 'Temperature Spike',
              subtitle: 'Notify if ≥ 38.2°C',
              value: _temperatureAlerts,
              onChanged: (value) {
                setState(() {
                  _temperatureAlerts = value;
                });
              },
            ),
            const SizedBox(height: 8),
            _buildToggleItem(
              context: context,
              icon: Icons.water_drop,
              title: 'SpO2 Drop',
              subtitle: 'Notify if < 95%',
              value: _spo2Alerts,
              onChanged: (value) {
                setState(() {
                  _spo2Alerts = value;
                });
              },
            ),
            const SizedBox(height: 24),
            // Notifications
            _buildSectionTitle(context, 'NOTIFICATIONS'),
            const SizedBox(height: 12),
            _buildToggleItem(
              context: context,
              icon: Icons.notifications_active,
              title: 'Push Notifications',
              subtitle: 'Receive real-time AI alerts if anomalies occur',
              value: _pushNotifications,
              onChanged: (value) {
                setState(() {
                  _pushNotifications = value;
                });
              },
            ),
            const SizedBox(height: 8),
            _buildToggleItem(
              context: context,
              icon: Icons.mail_outline,
              title: 'Email Summaries',
              subtitle: 'Weekly health reports',
              value: _emailSummaries,
              onChanged: (value) {
                setState(() {
                  _emailSummaries = value;
                });
              },
            ),
            const SizedBox(height: 24),
            // Data & Privacy
            _buildSectionTitle(context, 'DATA & PRIVACY'),
            const SizedBox(height: 12),
            _buildSettingsItem(
              context: context,
              icon: Icons.download,
              title: 'Export Health Data',
              subtitle: 'Download all your health records',
              trailing: const Icon(Icons.chevron_right),
            ),
            const SizedBox(height: 8),
            _buildSettingsItem(
              context: context,
              icon: Icons.security,
              title: 'Privacy Controls',
              subtitle: 'Manage data sharing permissions',
              trailing: const Icon(Icons.chevron_right),
            ),
            const SizedBox(height: 24),
            // Account
            _buildSectionTitle(context, 'ACCOUNT'),
            const SizedBox(height: 12),
            _buildSettingsItem(
              context: context,
              icon: Icons.help_outline,
              title: 'Help & Support',
              subtitle: 'Contact us or view FAQs',
              trailing: const Icon(Icons.chevron_right),
            ),
            const SizedBox(height: 8),
            _buildSettingsItem(
              context: context,
              icon: Icons.logout,
              title: 'Log Out',
              subtitle: 'Sign out of your account',
              trailing: const Icon(Icons.chevron_right),
              iconColor: AppTheme.accentRed,
              onTap: () {
                _showLogoutDialog(context);
              },
            ),
            const SizedBox(height: 8),
            _buildSettingsItem(
              context: context,
              icon: Icons.delete_outline,
              title: 'Delete Account',
              subtitle: 'Permanently delete your account',
              iconColor: AppTheme.accentRed,
              trailing: const Icon(Icons.chevron_right),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditProfileDialog(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user == null) return;

    final fullNameController = TextEditingController(text: user.fullName);
    final weightController =
        TextEditingController(text: user.weightKg.toStringAsFixed(1));
    final heightController =
        TextEditingController(text: user.heightCm.toStringAsFixed(1));
    final systolicController = TextEditingController(
      text: _extractBpValue(user.knownConditions, 'Systolic BP:') ?? '',
    );
    final diastolicController = TextEditingController(
      text: _extractBpValue(user.knownConditions, 'Diastolic BP:') ?? '',
    );

    final formKey = GlobalKey<FormState>();
    var selectedGender = user.gender.toLowerCase();
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Profile'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: fullNameController,
                        decoration:
                            const InputDecoration(labelText: 'Full Name'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedGender,
                        decoration: const InputDecoration(labelText: 'Gender'),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'female', child: Text('Female')),
                          DropdownMenuItem(
                              value: 'other', child: Text('Other')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedGender = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Weight (kg)'),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Enter a valid weight';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: heightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Height (cm)'),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Enter a valid height';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: systolicController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Systolic BP'),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Enter valid systolic BP';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: diastolicController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Diastolic BP'),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Enter valid diastolic BP';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }

                          final updatedUser = user.copyWith(
                            fullName: fullNameController.text.trim(),
                            gender: selectedGender,
                            weightKg:
                                double.parse(weightController.text.trim()),
                            heightCm:
                                double.parse(heightController.text.trim()),
                            knownConditions: [
                              'Systolic BP: ${systolicController.text.trim()}',
                              'Diastolic BP: ${diastolicController.text.trim()}',
                            ],
                          );

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            await authProvider.updateUserProfile(updatedUser);
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile updated successfully'),
                              ),
                            );
                          } catch (e) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              isSubmitting = false;
                            });
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Update failed: $e'),
                                backgroundColor: AppTheme.accentRed,
                              ),
                            );
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    fullNameController.dispose();
    weightController.dispose();
    heightController.dispose();
    systolicController.dispose();
    diastolicController.dispose();
  }

  String? _extractBpValue(List<String> conditions, String prefix) {
    final condition = conditions.firstWhere((item) => item.startsWith(prefix),
        orElse: () => '');
    if (condition.isEmpty) return null;
    return condition.replaceFirst(prefix, '').trim();
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppTheme.darkGray,
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildSettingsItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    Color iconColor = AppTheme.primaryBlue,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.mediumGray),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(icon, color: iconColor, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.darkGray,
                        ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildToggleItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.mediumGray),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(icon, color: AppTheme.primaryBlue, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.darkGray,
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primaryBlue,
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (!context.mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/welcome',
                (route) => false,
              );
            },
            child: const Text(
              'Log Out',
              style: TextStyle(color: AppTheme.accentRed),
            ),
          ),
        ],
      ),
    );
  }
}
