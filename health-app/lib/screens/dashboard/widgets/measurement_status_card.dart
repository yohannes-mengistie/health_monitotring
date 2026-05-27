import 'package:flutter/material.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/models/measurement_session.dart';

class MeasurementStatusCard extends StatefulWidget {
  final MeasurementState state;
  final int progress;
  final String instruction;
  final String? errorCode;
  final bool isUsingCachedData;

  const MeasurementStatusCard({
    Key? key,
    required this.state,
    required this.progress,
    required this.instruction,
    required this.errorCode,
    required this.isUsingCachedData,
  }) : super(key: key);

  @override
  State<MeasurementStatusCard> createState() => _MeasurementStatusCardState();
}

class _MeasurementStatusCardState extends State<MeasurementStatusCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _resolveAccentColor();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          _buildGauge(accentColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.state.label,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.isUsingCachedData) ...[
                      const SizedBox(width: 8),
                      _buildCachedChip(),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.instruction,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.darkGray,
                  ),
                ),
                if (widget.state.isError && widget.errorCode != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.errorCode!.replaceAll('_', ' '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.accentRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGauge(Color accentColor) {
    final progressValue = (widget.progress.clamp(0, 100)) / 100;
    final showProgress = widget.state.showsProgress;

    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.state.showsPulse)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final scale = 0.9 + (_pulseController.value * 0.2);
                final opacity = 0.2 + (0.3 * (1 - _pulseController.value));
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withOpacity(opacity),
                    ),
                  ),
                );
              },
            ),
          SizedBox(
            width: 66,
            height: 66,
            child: CircularProgressIndicator(
              value: showProgress ? progressValue : null,
              strokeWidth: 6,
              backgroundColor: accentColor.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          _buildGaugeCenter(accentColor, showProgress),
        ],
      ),
    );
  }

  Widget _buildGaugeCenter(Color accentColor, bool showProgress) {
    if (widget.state.isComplete) {
      return const Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 30);
    }

    if (widget.state.isError) {
      return const Icon(Icons.error, color: AppTheme.accentRed, size: 30);
    }

    if (!showProgress) {
      return Icon(Icons.fingerprint, color: accentColor, size: 30);
    }

    return Text(
      '${widget.progress.clamp(0, 100)}%',
      style: TextStyle(
        color: accentColor,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    );
  }

  Widget _buildCachedChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Cached',
        style: TextStyle(
          color: AppTheme.primaryBlue,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _resolveAccentColor() {
    switch (widget.state) {
      case MeasurementState.fingerDetected:
      case MeasurementState.stabilizing:
        return AppTheme.accentPurple;
      case MeasurementState.measuring:
        return AppTheme.primaryBlue;
      case MeasurementState.complete:
        return AppTheme.accentGreen;
      case MeasurementState.removeFinger:
        return AppTheme.accentOrange;
      case MeasurementState.error:
        return AppTheme.accentRed;
      case MeasurementState.ready:
      case MeasurementState.waitingForFinger:
      case MeasurementState.unknown:
        return AppTheme.darkGray;
    }
  }
}
