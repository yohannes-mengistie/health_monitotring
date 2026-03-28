import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:health_monitor_ai/config/app_theme.dart';
import 'package:health_monitor_ai/models/analysis_model.dart';
import 'package:health_monitor_ai/models/recommendation_model.dart';
import 'package:health_monitor_ai/providers/auth_provider.dart';
import 'package:health_monitor_ai/providers/health_provider.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({Key? key}) : super(key: key);

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  String? _selectedLanguageCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecommendation();
    });
  }

  Future<void> _loadRecommendation() async {
    final authProvider = context.read<AuthProvider>();
    final healthProvider = context.read<HealthProvider>();
    final user = authProvider.currentUser;
    if (user == null) {
      return;
    }

    final localeCode = Localizations.localeOf(context).languageCode;
    final selectedCode = _selectedLanguageCode ?? localeCode;
    final language =
        selectedCode.toLowerCase().startsWith('am') ? 'amharic' : 'english';

    await healthProvider.loadClinicalRecommendation(
      userId: user.id,
      token: authProvider.authToken,
      language: language,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Clinical Recommendations'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<HealthProvider>(
        builder: (context, healthProvider, _) {
          if (healthProvider.currentRecommendation == null) {
            if (healthProvider.isLoading) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  healthProvider.errorMessage ??
                      'No recommendation details available yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final recommendation = healthProvider.currentRecommendation!;
          final localeCode = Localizations.localeOf(context).languageCode;
          final parsedReport = _LocalizedReport.fromRawText(
            recommendation.actionPlan,
            recommendation.medicalDisclaimer,
          );

          final preferredLanguage = _selectedLanguageCode ?? localeCode;
          final reportVersion = parsedReport.versionFor(preferredLanguage) ??
              parsedReport.firstAvailable;

          if (reportVersion == null) {
            return const Center(
              child: Text('No recommendation details available yet.'),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildClinicalHeader(
                  context,
                  healthProvider.currentAnalysis,
                  recommendation,
                ),
                if (parsedReport.hasMultipleLanguages) ...[
                  const SizedBox(height: 20),
                  _buildLanguageToggle(
                      context, parsedReport, reportVersion.languageCode),
                ],
                const SizedBox(height: 20),
                ...reportVersion.sections.map(
                  (section) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildSectionCard(context, section),
                  ),
                ),
                if (reportVersion.disclaimer != null) ...[
                  const SizedBox(height: 8),
                  _buildDisclaimerCard(context, reportVersion.disclaimer!),
                ],
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildClinicalHeader(
    BuildContext context,
    HealthAnalysis? analysis,
    HealthRecommendation recommendation,
  ) {
    final riskLabel = analysis == null
        ? 'Unknown Risk'
        : '${analysis.riskLevel.name.toUpperCase()} RISK';
    final riskColor = _riskColor(analysis?.riskLevel);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryBlue,
            AppTheme.primaryBlue.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'AI Clinical Brief',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: riskColor.withOpacity(0.35)),
                ),
                child: Text(
                  riskLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Structured recommendation based on your latest analysis.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.white.withOpacity(0.9),
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Updated ${_formatDate(recommendation.updatedAt)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.white,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(
                  value: recommendation.completionPercentage / 100,
                  minHeight: 7,
                  backgroundColor: AppTheme.white.withOpacity(0.18),
                  valueColor:
                      const AlwaysStoppedAnimation(AppTheme.accentGreen),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageToggle(
    BuildContext context,
    _LocalizedReport report,
    String selectedCode,
  ) {
    final versions = report.availableVersions;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.mediumGray),
      ),
      child: Wrap(
        spacing: 10,
        children: versions.map((version) {
          final isSelected = version.languageCode == selectedCode;
          return ChoiceChip(
            selected: isSelected,
            label: Text(version.languageLabel),
            selectedColor: AppTheme.primaryBlue.withOpacity(0.15),
            checkmarkColor: AppTheme.primaryBlue,
            onSelected: (_) {
              setState(() {
                _selectedLanguageCode = version.languageCode;
              });
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, _ReportSection section) {
    final accent = _sectionColor(section.title);
    final icon = _sectionIcon(section.title);

    return Container(
      width: double.infinity,
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          if (section.paragraphs.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...section.paragraphs.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  line,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
          if (section.bullets.isNotEmpty) ...[
            const SizedBox(height: 2),
            ...section.bullets.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 8, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (section.numberedItems.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...section.numberedItems.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${entry.key + 1}',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildDisclaimerCard(
    BuildContext context,
    String text,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentOrange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentOrange.withOpacity(0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.accentOrange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.veryDarkGray,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Color _riskColor(RiskLevel? level) {
    switch (level) {
      case RiskLevel.low:
        return AppTheme.accentGreen;
      case RiskLevel.moderate:
        return AppTheme.accentOrange;
      case RiskLevel.high:
      case RiskLevel.critical:
        return AppTheme.accentRed;
      case null:
        return AppTheme.darkGray;
    }
  }

  Color _sectionColor(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('assessment') || lower.contains('ግምገማ')) {
      return AppTheme.primaryBlue;
    }
    if (lower.contains('focus') || lower.contains('ትኩረት')) {
      return AppTheme.accentOrange;
    }
    if (lower.contains('plan') || lower.contains('እቅድ')) {
      return AppTheme.accentGreen;
    }
    return AppTheme.accentPurple;
  }

  IconData _sectionIcon(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('assessment') || lower.contains('ግምገማ')) {
      return Icons.medical_information_outlined;
    }
    if (lower.contains('focus') || lower.contains('ትኩረት')) {
      return Icons.track_changes;
    }
    if (lower.contains('plan') || lower.contains('እቅድ')) {
      return Icons.task_alt;
    }
    return Icons.auto_awesome;
  }

  String _formatDate(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _LocalizedReport {
  final _ReportVersion? english;
  final _ReportVersion? amharic;

  const _LocalizedReport({
    this.english,
    this.amharic,
  });

  factory _LocalizedReport.fromRawText(String raw, String fallbackDisclaimer) {
    final normalized = raw.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return _LocalizedReport(
        english: _ReportVersion(
          languageCode: 'en',
          languageLabel: 'English',
          sections: [],
          disclaimer: fallbackDisclaimer,
        ),
      );
    }

    final parts = normalized
        .split(RegExp(r'\n?-{10,}\n?'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    _ReportVersion? en;
    _ReportVersion? am;

    for (final part in parts) {
      final version = _ReportVersion.parse(
        part,
        fallbackDisclaimer,
        _containsAmharic(part) ? 'am' : 'en',
      );

      if (version.languageCode == 'am') {
        am = version;
      } else {
        en = version;
      }
    }

    if (parts.length == 1 && en == null && am != null) {
      return _LocalizedReport(amharic: am);
    }
    if (parts.length == 1 && am == null && en != null) {
      return _LocalizedReport(english: en);
    }

    return _LocalizedReport(english: en, amharic: am);
  }

  bool get hasMultipleLanguages => english != null && amharic != null;

  List<_ReportVersion> get availableVersions {
    return [
      if (english != null) english!,
      if (amharic != null) amharic!,
    ];
  }

  _ReportVersion? get firstAvailable {
    if (english != null) return english;
    return amharic;
  }

  _ReportVersion? versionFor(String languageCode) {
    if (languageCode.toLowerCase().startsWith('am')) {
      return amharic ?? english;
    }
    return english ?? amharic;
  }

  static bool _containsAmharic(String text) {
    return RegExp(r'[\u1200-\u137F]').hasMatch(text);
  }
}

class _ReportVersion {
  final String languageCode;
  final String languageLabel;
  final List<_ReportSection> sections;
  final String? disclaimer;

  const _ReportVersion({
    required this.languageCode,
    required this.languageLabel,
    required this.sections,
    required this.disclaimer,
  });

  factory _ReportVersion.parse(
    String text,
    String fallbackDisclaimer,
    String languageCode,
  ) {
    final lines = text.split('\n');
    final sections = <_ReportSection>[];
    String? currentTitle;
    final buffer = <String>[];
    String? disclaimer;

    void flushSection() {
      if (currentTitle == null) return;
      sections.add(_ReportSection.parse(currentTitle, buffer));
      buffer.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('###')) {
        flushSection();
        currentTitle = _cleanText(trimmed.replaceFirst('###', ''));
        continue;
      }

      if (trimmed.startsWith('*Disclaimer:') || trimmed.startsWith('*ማሳሰቢያ:')) {
        disclaimer = _cleanText(trimmed);
        continue;
      }

      if (currentTitle == null) {
        currentTitle = languageCode == 'am' ? 'ምክር' : 'Recommendation';
      }

      buffer.add(trimmed);
    }

    flushSection();

    return _ReportVersion(
      languageCode: languageCode,
      languageLabel: languageCode == 'am' ? 'አማርኛ' : 'English',
      sections: sections,
      disclaimer: disclaimer ?? fallbackDisclaimer,
    );
  }

  static String _cleanText(String value) {
    return value.replaceAll('**', '').replaceAll('*', '').trim();
  }
}

class _ReportSection {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
  final List<String> numberedItems;

  const _ReportSection({
    required this.title,
    required this.paragraphs,
    required this.bullets,
    required this.numberedItems,
  });

  factory _ReportSection.parse(String title, List<String> rawLines) {
    final paragraphs = <String>[];
    final bullets = <String>[];
    final numbered = <String>[];

    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('*')) {
        bullets.add(_stripPrefix(line.replaceFirst(RegExp(r'^\*+\s*'), '')));
        continue;
      }

      if (RegExp(r'^\d+\.\s+').hasMatch(line)) {
        numbered.add(_stripPrefix(line.replaceFirst(RegExp(r'^\d+\.\s+'), '')));
        continue;
      }

      paragraphs.add(_stripPrefix(line));
    }

    return _ReportSection(
      title: title,
      paragraphs: paragraphs,
      bullets: bullets,
      numberedItems: numbered,
    );
  }

  static String _stripPrefix(String value) {
    return value.replaceAll('**', '').trim();
  }
}
