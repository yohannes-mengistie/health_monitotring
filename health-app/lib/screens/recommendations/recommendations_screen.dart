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
  final Set<String> _selectedSymptomKeys = <String>{};
  bool _noQuickSymptoms = false;
  int _followUpIndex = 0;
  final Map<String, _OpqrstAnswers> _opqrstAnswers = {};
  bool? _redFlagAnswer;

  bool _hasHypertension = false;
  bool _hasDiabetes = false;
  bool _hasHighCholesterol = false;
  String? _medicationAnswer;
  bool _noBackgroundConditions = false;

  bool _isAmharic(BuildContext context) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final selectedCode = _selectedLanguageCode ?? localeCode;
    return selectedCode.toLowerCase().startsWith('am');
  }

  String _t(BuildContext context, String key) {
    final isAmharic = _isAmharic(context);
    final entry = _uiText[key];
    if (entry == null) {
      return key;
    }
    return isAmharic
        ? (entry['am'] ?? entry['en'] ?? key)
        : (entry['en'] ?? key);
  }

  List<String> _onsetOptions(BuildContext context) {
    return _isAmharic(context)
        ? ['አሁን', 'ከ1 ሰዓት በታች', 'ዛሬ', 'ቀስ በቀስ']
        : ['Just now', '< 1 hour', 'Today', 'Gradually'];
  }

  List<String> _timingOptions(BuildContext context) {
    return _isAmharic(context)
        ? ['ቋሚ', 'እየመለሰ የሚመጣ']
        : ['Constant', 'Intermittent'];
  }

  List<String> _medicationOptions(BuildContext context) {
    return _isAmharic(context)
        ? ['አዎ', 'አይ', 'ረስቻለሁ']
        : ['Yes', 'No', 'Forgot'];
  }

  List<_SymptomOption> _symptomOptions(BuildContext context) {
    final isAmharic = _isAmharic(context);
    return [
      _SymptomOption(
        key: 'chest_pain',
        label: isAmharic ? 'የደረት ህመም' : 'Chest Pain',
        icon: Icons.favorite_outline,
        isHighRisk: true,
        qualityQuestion:
            isAmharic ? 'ህመሙ እንዴት ይሰማል?' : 'How does the pain feel?',
        qualityOptions: isAmharic
            ? ['ግፊት', 'ስር የሚቆርጥ', 'የሚነድ', 'ጥብቅነት']
            : ['Pressure', 'Sharp', 'Burning', 'Tightness'],
      ),
      _SymptomOption(
        key: 'dizziness',
        label: isAmharic ? 'ራስ ማዞር' : 'Dizziness',
        icon: Icons.motion_photos_on_outlined,
        isHighRisk: true,
        qualityQuestion:
            isAmharic ? 'የሚሰማዎትን ምን ይገልጻል?' : 'What best describes it?',
        qualityOptions: isAmharic
            ? ['ክፍሉ እንደሚዞር', 'ድንጋጤ/ብርሃን ማለት', 'ሚዛን መጣስ']
            : ['Room spinning', 'Faint/lightheaded', 'Off-balance'],
      ),
      _SymptomOption(
        key: 'shortness_of_breath',
        label: isAmharic ? 'የትንፋሽ እጥረት' : 'Shortness of Breath',
        icon: Icons.air,
        qualityQuestion: isAmharic ? 'በመቼ ጊዜ ይሻላል?' : 'When is it worse?',
        qualityOptions: isAmharic
            ? ['በእረፍት ጊዜ', 'እንቅስቃሴ ሲኖር', 'ሲደበቅ/ሲጋለጥ', 'በድንገት ይመጣ']
            : ['At rest', 'With activity', 'Lying down', 'Sudden episodes'],
      ),
      _SymptomOption(
        key: 'headache',
        label: isAmharic ? 'ራስ ህመም' : 'Headache',
        icon: Icons.psychology_alt_outlined,
        qualityQuestion: isAmharic ? 'የህመሙ አይነት' : 'Pain quality',
        qualityOptions: isAmharic
            ? ['የሚያምር', 'ግፊት', 'ስር የሚቆርጥ', 'ገመድ እንደተጠበቀ']
            : ['Throbbing', 'Pressure', 'Sharp', 'Band-like tightness'],
      ),
      _SymptomOption(
        key: 'fatigue',
        label: isAmharic ? 'ድካም' : 'Fatigue',
        icon: Icons.battery_alert_outlined,
        qualityQuestion:
            isAmharic ? 'እንዴት ይገልጹታል?' : 'How would you describe it?',
        qualityOptions: isAmharic
            ? ['ዝቅተኛ ኃይል', 'እንቅልፍ መስሎኝ', 'የጡንቻ ድካም', 'የአእምሮ ጭጋግ']
            : ['Low energy', 'Sleepy', 'Muscle weakness', 'Mental fog'],
      ),
    ];
  }

  List<_SymptomOption> _selectedSymptoms(BuildContext context) {
    return _symptomOptions(context)
        .where((item) => _selectedSymptomKeys.contains(item.key))
        .toList();
  }

  _SymptomOption? _currentSymptom(BuildContext context) {
    final selected = _selectedSymptoms(context);
    if (selected.isEmpty) return null;
    final index = _followUpIndex.clamp(0, selected.length - 1);
    return selected[index];
  }

  _SymptomOption? _primarySymptom(BuildContext context) {
    final selected = _selectedSymptoms(context);
    if (selected.isEmpty) return null;
    return selected.first;
  }

  _OpqrstAnswers _answersFor(String symptomKey) {
    return _opqrstAnswers.putIfAbsent(
      symptomKey,
      () => const _OpqrstAnswers(),
    );
  }

  bool _isSymptomAssessmentComplete(String symptomKey) {
    final answers = _opqrstAnswers[symptomKey];
    if (answers == null) return false;
    return answers.onset != null &&
        answers.quality != null &&
        answers.timing != null &&
        answers.severity != null;
  }

  bool _hasAnyHighRiskSymptom(BuildContext context) {
    for (final symptom in _selectedSymptoms(context)) {
      if (symptom.isHighRisk) {
        return true;
      }
    }
    return false;
  }

  bool _isCoreAssessmentComplete(BuildContext context) {
    if (_noQuickSymptoms) {
      return _medicationAnswer != null;
    }

    if (_selectedSymptomKeys.isEmpty) return false;

    final selected = _selectedSymptoms(context);
    for (final symptom in selected) {
      if (!_isSymptomAssessmentComplete(symptom.key)) {
        return false;
      }
    }

    if (_medicationAnswer == null) return false;
    if (_hasAnyHighRiskSymptom(context) && _redFlagAnswer == null) return false;
    return true;
  }

  static const Map<String, Map<String, String>> _uiText = {
    'title': {
      'en': 'AI Clinical Recommendations',
      'am': 'የAI ክሊኒካል ምክሮች',
    },
    'languageTooltip': {
      'en': 'Change recommendation language',
      'am': 'የምክር ቋንቋ ቀይር',
    },
    'noBriefTitle': {
      'en': 'No Clinical Brief Yet',
      'am': 'ገና የክሊኒካል ማጠቃለያ የለም',
    },
    'noBriefMessage': {
      'en': 'No recommendation details available yet.',
      'am': 'የምክር ዝርዝሮች ገና አልተገኙም።',
    },
    'getRecommendation': {
      'en': 'Get Recommendation',
      'am': 'ምክር አግኝ',
    },
    'tellAi': {
      'en': 'how you feel now ?',
      'am': 'አሁን ምን ይሰማሃል?',
    },
    'quickSymptoms': {
      'en': 'Quick Symptoms',
      'am': 'ፈጣን ምልክቶች',
    },
    'quickSymptomsHint': {
      'en': 'Select all symptoms that apply, or skip if you have none.',
      'am': 'ስለሚፈልጉ ምልክቶች ሁሉንም ይምረጡ፣ የለም ከሆነ ይዝለሉ።',
    },
    'noQuickSymptoms': {
      'en': 'No quick symptoms right now',
      'am': 'በአሁኑ ጊዜ ፈጣን ምልክት የለም',
    },
    'primarySymptom': {
      'en': 'Primary symptom for OPQRST follow-up',
      'am': 'ለOPQRST ተከታታይ ዋና ምልክት',
    },
    'followUp': {
      'en': 'Follow-up (OPQRST)',
      'am': 'ተከታታይ (OPQRST)',
    },
    'onsetTitle': {
      'en': 'Onset: When did this start?',
      'am': 'መጀመሪያ: መቼ ጀመረዎ?',
    },
    'timingTitle': {
      'en': 'Timing: Is it constant or intermittent?',
      'am': 'ጊዜ: ቋሚ ነው ወይስ እየመለሰ የሚመጣ?',
    },
    'severityLabel': {
      'en': 'Severity',
      'am': 'የህመም ጥንካሬ',
    },
    'redFlag': {
      'en': 'Red Flag Check',
      'am': 'የአደገኛ ምልክት ምርመራ',
    },
    'redFlagQuestion': {
      'en':
          'Are you also experiencing numbness, slurred speech, or severe pressure?',
      'am': 'የሰውነት መደንዘዝ፣ የመንተባተብ (ንግግር መክበድ) ወይም ከፍተኛ ግፊት እየተሰማዎት ነው?',
    },
    'callEmergency': {
      'en': 'CALL EMERGENCY',
      'am': 'አስቸኳይ ይደውሉ',
    },
    'emergencyMessage': {
      'en':
          'Emergency warning: seek immediate medical help or call emergency services now.',
      'am': 'አስቸኳይ ማስጠንቀቂያ: አሁን ወዲያውኑ የህክምና እርዳታ ይፈልጉ ወይም አስቸኳይ አገልግሎት ይደውሉ።',
    },
    'yes': {
      'en': 'Yes',
      'am': 'አዎ',
    },
    'no': {
      'en': 'No',
      'am': 'አይ',
    },
    'background': {
      'en': 'Background',
      'am': 'ጀርባ መረጃ',
    },
    'hypertension': {
      'en': 'Hypertension',
      'am': 'የደም ግፊት',
    },
    'diabetes': {
      'en': 'Diabetes',
      'am': 'የስኳር በሽታ',
    },
    'cholesterol': {
      'en': 'High Cholesterol',
      'am': 'ከፍተኛ ኮሌስተሮል',
    },
    'medicationQuestion': {
      'en': 'Did you take your prescribed medication today?',
      'am': 'ዛሬ የታዘዘውን መድኃኒት ወስደዋል?',
    },
    'submit': {
      'en': 'Submit to AI',
      'am': 'ለAI ላክ',
    },
    'submitting': {
      'en': 'Submitting...',
      'am': 'በመላክ ላይ...',
    },
    'completeAll': {
      'en': 'Complete symptom, OPQRST, and medication check to submit.',
      'am': 'ለማቅረብ ምልክት፣ OPQRST እና መድሀኒት መረጃ ይሙሉ።',
    },
    'completeMedication': {
      'en': 'Complete the medication check to submit.',
      'am': 'ለማቅረብ የመድሀኒት መረጃ ብቻ ይሙሉ።',
    },
    'clinicalActionPlan': {
      'en': 'Clinical Action Plan',
      'am': 'የክሊኒካል የተግባር እቅድ',
    },
    'noDetails': {
      'en': 'No recommendation details available yet.',
      'am': 'የምክር ዝርዝሮች ገና አልተገኙም።',
    },
    'aiBrief': {
      'en': 'AI Clinical Brief',
      'am': 'የAI ክሊኒካል ማጠቃለያ',
    },
    'briefSubtitle': {
      'en':
          'Structured and safety-first recommendation based on your latest analysis.',
      'am': 'በመጨረሻ ትንታኔዎ ላይ የተመሰረተ የተዋቀረ እና የደህንነት ቅድሚያ ያለው ምክር።',
    },
    'updatedLabel': {
      'en': 'Updated',
      'am': 'የተዘመነ',
    },
    'noQuickSymptomsReported': {
      'en': 'No quick symptoms reported',
      'am': 'ፈጣን ምልክት አልተመዘገበም',
    },
    'newRecommendation': {
      'en': 'Get New Recommendation',
      'am': 'አዲስ ምክር አግኝ',
    },
    'generatingRecommendation': {
      'en': 'Generating Recommendation...',
      'am': 'ምክር በመፍጠር ላይ...',
    },
    'sections': {
      'en': 'Sections',
      'am': 'ክፍሎች',
    },
    'actionItems': {
      'en': 'Action Items',
      'am': 'የተግባር ነጥቦች',
    },
    'amharicLabel': {
      'en': 'Amharic',
      'am': 'አማርኛ',
    },
    'englishLabel': {
      'en': 'English',
      'am': 'እንግሊዝኛ',
    },
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedLanguageCode = Localizations.localeOf(context).languageCode;
      });
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

    final selectedSymptom = _primarySymptom(context);
    if (!_noQuickSymptoms && selectedSymptom == null) {
      return;
    }

    if (!_isCoreAssessmentComplete(context)) {
      return;
    }

    final structuredAssessment = _buildStructuredAssessment(context);

    final selectedLabels = _noQuickSymptoms
        ? _t(context, 'noQuickSymptomsReported')
        : _buildSymptomSummary(context);
    final vitalsSummary = _buildVitalsSummary(healthProvider);
    final feelingParts = <String>[selectedLabels];
    if (vitalsSummary != null) {
      feelingParts.add(vitalsSummary);
    }

    await healthProvider.loadClinicalRecommendation(
      userId: user.id,
      token: authProvider.authToken,
      language: language,
      currentFeeling: feelingParts.join(' | '),
      structuredAssessment: structuredAssessment,
    );
  }

  Future<void> _showLanguagePicker() async {
    final localeCode = Localizations.localeOf(context).languageCode;
    final currentCode = _selectedLanguageCode ?? localeCode;

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(_t(context, 'englishLabel')),
                trailing: currentCode.startsWith('en')
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, 'en'),
              ),
              ListTile(
                leading: const Icon(Icons.translate),
                title: Text(_t(context, 'amharicLabel')),
                trailing: currentCode.startsWith('am')
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, 'am'),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || selected == currentCode) {
      return;
    }

    setState(() {
      _selectedLanguageCode = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final theme = _isAmharic(context)
        ? baseTheme.copyWith(
            textTheme: _amharicTextTheme(baseTheme.textTheme),
          )
        : baseTheme;

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t(context, 'title')),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.language),
              tooltip: _t(context, 'languageTooltip'),
              onPressed: _showLanguagePicker,
            ),
          ],
        ),
        body: Consumer<HealthProvider>(
          builder: (context, healthProvider, _) {
            if (healthProvider.currentRecommendation == null) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        if (healthProvider.isLoading) ...[
                          const SizedBox(height: 2),
                          const LinearProgressIndicator(minHeight: 2),
                          const SizedBox(height: 12),
                        ],
                        _buildPromptComposer(
                          context,
                          healthProvider,
                          minHeight: _promptMinHeight(context),
                        ),
                      ],
                    ),
                  );
                },
              );
            }

            final recommendation = healthProvider.currentRecommendation!;
            final localeCode = Localizations.localeOf(context).languageCode;
            final parsedReport = _LocalizedReport.fromRawText(
              _normalizeRecommendationText(recommendation.actionPlan),
              recommendation.medicalDisclaimer,
            );

            final preferredLanguage = _selectedLanguageCode ?? localeCode;
            final reportVersion = parsedReport.versionFor(preferredLanguage) ??
                parsedReport.firstAvailable;

            if (reportVersion == null) {
              return Center(
                child: Text(_t(context, 'noDetails')),
              );
            }

            return Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppTheme.primaryBlue.withOpacity(0.08),
                        AppTheme.lightGray,
                        AppTheme.lightGray,
                      ],
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPromptComposer(
                          context,
                          healthProvider,
                          minHeight: _promptMinHeight(context),
                        ),
                        const SizedBox(height: 16),
                        _buildClinicalHeader(
                          context,
                          healthProvider.currentAnalysis,
                          recommendation,
                          onRefreshPressed: _loadRecommendation,
                          isRefreshing: healthProvider.isLoading,
                        ),
                        if (parsedReport.hasMultipleLanguages) ...[
                          const SizedBox(height: 16),
                          _buildLanguageToggle(
                            context,
                            parsedReport,
                            reportVersion.languageCode,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildReportSummaryCard(
                          context: context,
                          recommendation: recommendation,
                          sectionCount: reportVersion.sections.length,
                          itemCount: _contentItemCount(reportVersion),
                          languageCode: reportVersion.languageCode,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 18,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _t(context, 'clinicalActionPlan'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...reportVersion.sections.map(
                          (section) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _buildSectionCard(context, section),
                          ),
                        ),
                        if (reportVersion.disclaimer != null) ...[
                          const SizedBox(height: 8),
                          _buildDisclaimerCard(
                              context, reportVersion.disclaimer!),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
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
      ),
    );
  }

  Widget _buildPromptComposer(
      BuildContext context, HealthProvider healthProvider,
      {double? minHeight}) {
    final symptom = _currentSymptom(context);
    final isAmharic = _isAmharic(context);
    final selectedSymptoms = _selectedSymptoms(context);
    final totalSymptoms = selectedSymptoms.length;
    final hasSymptom = symptom != null;
    final currentIndex =
        _followUpIndex.clamp(0, totalSymptoms > 0 ? totalSymptoms - 1 : 0);
    final currentKey = hasSymptom ? symptom.key : null;
    final answers = currentKey == null ? null : _answersFor(currentKey);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.mediumGray.withOpacity(0.8)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.psychology_alt_outlined,
                    color: AppTheme.primaryBlue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _t(context, 'tellAi'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildSectionLabel(
              context,
              icon: Icons.bolt,
              label: _t(context, 'quickSymptoms'),
            ),
            const SizedBox(height: 4),
            Text(
              _t(context, 'quickSymptomsHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lightGray,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.mediumGray.withOpacity(0.8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _t(context, 'noQuickSymptoms'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _noQuickSymptoms,
                    onChanged: (value) {
                      setState(() {
                        _noQuickSymptoms = value;
                        if (value) {
                          _selectedSymptomKeys.clear();
                          _opqrstAnswers.clear();
                          _followUpIndex = 0;
                          _redFlagAnswer = null;
                        }
                      });
                    },
                    activeColor: AppTheme.primaryBlue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (!_noQuickSymptoms) ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _symptomOptions(context).map((option) {
                  final selected = _selectedSymptomKeys.contains(option.key);
                  final isHighRisk = option.isHighRisk;

                  return InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      setState(() {
                        _noQuickSymptoms = false;
                        if (selected) {
                          _selectedSymptomKeys.remove(option.key);
                          _opqrstAnswers.remove(option.key);
                        } else {
                          _selectedSymptomKeys.add(option.key);
                          _answersFor(option.key);
                        }

                        if (_selectedSymptomKeys.isEmpty) {
                          _redFlagAnswer = null;
                          _followUpIndex = 0;
                          return;
                        }

                        final total = _selectedSymptoms(context).length;
                        if (_followUpIndex >= total) {
                          _followUpIndex = total - 1;
                        }

                        if (!_hasAnyHighRiskSymptom(context)) {
                          _redFlagAnswer = null;
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.primaryBlue.withOpacity(0.12)
                            : AppTheme.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? AppTheme.primaryBlue
                              : (isHighRisk
                                  ? AppTheme.accentRed.withOpacity(0.45)
                                  : AppTheme.mediumGray),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: selected
                                ? AppTheme.primaryBlue.withOpacity(0.08)
                                : Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            option.icon,
                            size: 17,
                            color: selected
                                ? AppTheme.primaryBlue
                                : (isHighRisk
                                    ? AppTheme.accentRed
                                    : AppTheme.darkGray),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            option.label,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: AppTheme.veryDarkGray,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: AppTheme.primaryBlue,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (!_noQuickSymptoms && symptom != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: AppTheme.mediumGray.withOpacity(0.7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel(
                      context,
                      icon: Icons.assignment_turned_in_outlined,
                      label: _t(context, 'followUp'),
                    ),
                    if (totalSymptoms > 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${symptom.label} (${currentIndex + 1}/$totalSymptoms)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.darkGray,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildChoiceField(
                      context,
                      title: _t(context, 'onsetTitle'),
                      icon: Icons.schedule_outlined,
                      options: _onsetOptions(context),
                      selectedValue: answers?.onset,
                      onSelected: (value) {
                        setState(() {
                          _opqrstAnswers[currentKey!] =
                              answers!.copyWith(onset: value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildChoiceField(
                      context,
                      title: isAmharic
                          ? 'ጥራት: ${symptom.qualityQuestion}'
                          : 'Quality: ${symptom.qualityQuestion}',
                      icon: Icons.health_and_safety_outlined,
                      options: symptom.qualityOptions,
                      selectedValue: answers?.quality,
                      onSelected: (value) {
                        setState(() {
                          _opqrstAnswers[currentKey!] =
                              answers!.copyWith(quality: value);
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.mediumGray.withOpacity(0.8)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_hospital_outlined,
                            color: AppTheme.primaryBlue,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_t(context, 'severityLabel')}: ${answers?.severity?.round() ?? 5}/10',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Slider(
                      value: answers?.severity ?? 5,
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: (answers?.severity ?? 5).round().toString(),
                      onChanged: (value) {
                        setState(() {
                          _opqrstAnswers[currentKey!] =
                              answers!.copyWith(severity: value);
                        });
                      },
                    ),
                    const SizedBox(height: 2),
                    _buildChoiceField(
                      context,
                      title: _t(context, 'timingTitle'),
                      icon: Icons.timelapse_outlined,
                      options: _timingOptions(context),
                      selectedValue: answers?.timing,
                      onSelected: (value) {
                        setState(() {
                          _opqrstAnswers[currentKey!] =
                              answers!.copyWith(timing: value);
                        });
                      },
                    ),
                    if (totalSymptoms > 1) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: currentIndex > 0
                                  ? () {
                                      setState(() {
                                        _followUpIndex = currentIndex - 1;
                                      });
                                    }
                                  : null,
                              child: const Text('Previous'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: currentIndex < totalSymptoms - 1
                                  ? () {
                                      setState(() {
                                        _followUpIndex = currentIndex + 1;
                                      });
                                    }
                                  : null,
                              child: const Text('Next'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (!_noQuickSymptoms && _hasAnyHighRiskSymptom(context)) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: AppTheme.accentRed.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.priority_high_rounded,
                          color: AppTheme.accentRed,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _t(context, 'redFlag'),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: AppTheme.accentRed,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t(context, 'redFlagQuestion'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: [
                        ChoiceChip(
                          label: Text(_t(context, 'yes')),
                          selected: _redFlagAnswer == true,
                          selectedColor: AppTheme.accentRed.withOpacity(0.2),
                          onSelected: (_) {
                            setState(() {
                              _redFlagAnswer = true;
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(_t(context, 'no')),
                          selected: _redFlagAnswer == false,
                          selectedColor: AppTheme.accentGreen.withOpacity(0.2),
                          onSelected: (_) {
                            setState(() {
                              _redFlagAnswer = false;
                            });
                          },
                        ),
                      ],
                    ),
                    if (_redFlagAnswer == true) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_t(context, 'emergencyMessage')),
                                backgroundColor: AppTheme.accentRed,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentRed,
                            foregroundColor: AppTheme.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.call),
                          label: Text(
                            _t(context, 'callEmergency'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.lightGray,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.mediumGray.withOpacity(0.7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionLabel(
                    context,
                    icon: Icons.medical_information_outlined,
                    label: _t(context, 'background'),
                  ),
                  const SizedBox(height: 6),
                  _buildConditionToggle(
                    context,
                    label: _isAmharic(context)
                        ? 'ሌላ የታሪክ በሽታ የለኝም'
                        : 'No background conditions',
                    value: _noBackgroundConditions,
                    onChanged: (value) {
                      setState(() {
                        _noBackgroundConditions = value;
                        if (value) {
                          _hasHypertension = false;
                          _hasDiabetes = false;
                          _hasHighCholesterol = false;
                        }
                      });
                    },
                  ),
                  _buildConditionToggle(
                    context,
                    label: _t(context, 'hypertension'),
                    value: _hasHypertension,
                    enabled: !_noBackgroundConditions,
                    onChanged: (value) {
                      setState(() {
                        _hasHypertension = value;
                        if (value) {
                          _noBackgroundConditions = false;
                        }
                      });
                    },
                  ),
                  _buildConditionToggle(
                    context,
                    label: _t(context, 'diabetes'),
                    value: _hasDiabetes,
                    enabled: !_noBackgroundConditions,
                    onChanged: (value) {
                      setState(() {
                        _hasDiabetes = value;
                        if (value) {
                          _noBackgroundConditions = false;
                        }
                      });
                    },
                  ),
                  _buildConditionToggle(
                    context,
                    label: _t(context, 'cholesterol'),
                    value: _hasHighCholesterol,
                    enabled: !_noBackgroundConditions,
                    onChanged: (value) {
                      setState(() {
                        _hasHighCholesterol = value;
                        if (value) {
                          _noBackgroundConditions = false;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  _buildChoiceField(
                    context,
                    title: _t(context, 'medicationQuestion'),
                    icon: Icons.medication_outlined,
                    options: _medicationOptions(context),
                    selectedValue: _medicationAnswer,
                    onSelected: (value) {
                      setState(() {
                        _medicationAnswer = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: healthProvider.isLoading ||
                        !_isCoreAssessmentComplete(context)
                    ? null
                    : _loadRecommendation,
                icon: healthProvider.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  healthProvider.isLoading
                      ? _t(context, 'submitting')
                      : _t(context, 'submit'),
                ),
              ),
            ),
            if (!_isCoreAssessmentComplete(context)) ...[
              const SizedBox(height: 8),
              Text(
                _noQuickSymptoms
                    ? _t(context, 'completeMedication')
                    : _t(context, 'completeAll'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.darkGray,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _promptMinHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final available =
        media.size.height - media.padding.top - kToolbarHeight - 40;
    return available > 0 ? available : 0;
  }

  TextTheme _amharicTextTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: _amharicStyle(base.displayLarge),
      displayMedium: _amharicStyle(base.displayMedium),
      displaySmall: _amharicStyle(base.displaySmall),
      headlineLarge: _amharicStyle(base.headlineLarge),
      headlineMedium: _amharicStyle(base.headlineMedium),
      headlineSmall: _amharicStyle(base.headlineSmall),
      titleLarge: _amharicStyle(base.titleLarge),
      titleMedium: _amharicStyle(base.titleMedium),
      titleSmall: _amharicStyle(base.titleSmall),
      bodyLarge: _amharicStyle(base.bodyLarge),
      bodyMedium: _amharicStyle(base.bodyMedium),
      bodySmall: _amharicStyle(base.bodySmall),
      labelLarge: _amharicStyle(base.labelLarge),
      labelMedium: _amharicStyle(base.labelMedium),
      labelSmall: _amharicStyle(base.labelSmall),
    );
  }

  TextStyle? _amharicStyle(TextStyle? style) {
    if (style == null) return null;
    return style.copyWith(
      fontFamily: 'NotoSansEthiopic',
      fontFamilyFallback: const [
        'Noto Sans Ethiopic',
        'NotoSansEthiopic',
        'Noto Sans',
        'sans-serif',
      ],
      height: 1.5,
      letterSpacing: 0.1,
    );
  }

  Widget _buildSectionLabel(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildConditionToggle(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: enabled ? null : AppTheme.darkGray,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.mediumGray.withOpacity(0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: labelStyle,
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeColor: AppTheme.primaryBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceField(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> options,
    required String? selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.primaryBlue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final selected = selectedValue == option;
            return ChoiceChip(
              label: Text(option),
              selected: selected,
              selectedColor: AppTheme.primaryBlue.withOpacity(0.16),
              onSelected: (_) => onSelected(option),
            );
          }).toList(),
        ),
      ],
    );
  }

  Map<String, dynamic> _buildStructuredAssessment(BuildContext context) {
    final primarySymptom = _primarySymptom(context);
    final conditions = <String>[];
    if (_hasHypertension) conditions.add('Hypertension');
    if (_hasDiabetes) conditions.add('Diabetes');
    if (_hasHighCholesterol) conditions.add('High Cholesterol');

    final symptomList = _selectedSymptoms(context)
        .map(
          (item) => {
            'key': item.key,
            'label': item.label,
            'high_risk': item.isHighRisk,
          },
        )
        .toList();

    final opqrstList = _selectedSymptoms(context).map((symptom) {
      final answers = _opqrstAnswers[symptom.key];
      return {
        'key': symptom.key,
        'label': symptom.label,
        'quality_question': symptom.qualityQuestion,
        'onset': answers?.onset,
        'quality': answers?.quality,
        'severity': answers?.severity?.round(),
        'timing': answers?.timing,
      };
    }).toList();

    return {
      'framework': 'OPQRST',
      'no_quick_symptoms': _noQuickSymptoms,
      'symptom': primarySymptom == null
          ? null
          : {
              'key': primarySymptom.key,
              'label': primarySymptom.label,
              'high_risk': primarySymptom.isHighRisk,
            },
      'symptoms': symptomList,
      'triage': {
        'red_flag_question': _hasAnyHighRiskSymptom(context)
            ? 'Numbness, slurred speech, or severe pressure'
            : null,
        'red_flag_yes': _hasAnyHighRiskSymptom(context) ? _redFlagAnswer : null,
      },
      'opqrst': primarySymptom == null
          ? null
          : {
              'onset': _opqrstAnswers[primarySymptom.key]?.onset,
              'quality_question': primarySymptom.qualityQuestion,
              'quality': _opqrstAnswers[primarySymptom.key]?.quality,
              'severity': _opqrstAnswers[primarySymptom.key]?.severity?.round(),
              'timing': _opqrstAnswers[primarySymptom.key]?.timing,
            },
      'opqrst_by_symptom': opqrstList,
      'background': {
        'known_conditions': conditions,
        'medication_taken_today': _medicationAnswer,
      },
      'submitted_at': DateTime.now().toIso8601String(),
    };
  }

  String _buildSymptomSummary(BuildContext context) {
    final symptoms = _selectedSymptoms(context);
    if (symptoms.isEmpty) {
      return _t(context, 'noQuickSymptomsReported');
    }

    return symptoms.map((symptom) {
      final answers = _opqrstAnswers[symptom.key];
      final details = <String>[];
      if (answers?.onset != null) details.add('onset ${answers!.onset}');
      if (answers?.quality != null) details.add('quality ${answers!.quality}');
      if (answers?.severity != null) {
        details.add('severity ${answers!.severity!.round()}/10');
      }
      if (answers?.timing != null) details.add('timing ${answers!.timing}');

      if (details.isEmpty) {
        return symptom.label;
      }

      return '${symptom.label} (${details.join(', ')})';
    }).join('; ');
  }

  String _normalizeRecommendationText(String text) {
    return text.replaceAll('ቪታሚኖች', 'የቫይታል');
  }

  String? _buildVitalsSummary(HealthProvider healthProvider) {
    final vitals = healthProvider.currentVitals;
    if (vitals == null) return null;

    final spo2 = vitals.spo2.toStringAsFixed(1);
    final temp = vitals.temperature.toStringAsFixed(1);
    return 'Vitals: HR ${vitals.heartRate} bpm, SpO2 $spo2%, Temp $temp C, BP ${vitals.systolicBP}/${vitals.diastolicBP}.';
  }

  Widget _buildClinicalHeader(BuildContext context, HealthAnalysis? analysis,
      HealthRecommendation recommendation,
      {required VoidCallback onRefreshPressed, required bool isRefreshing}) {
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
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _t(context, 'aiBrief'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppTheme.white,
                      fontWeight: FontWeight.w700,
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
                // child: Text(
                //   riskLabel,
                //   style: Theme.of(context).textTheme.labelLarge?.copyWith(
                //         color: AppTheme.white,
                //         fontWeight: FontWeight.w700,
                //       ),
                // ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _t(context, 'briefSubtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.white.withOpacity(0.9),
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isRefreshing ? null : onRefreshPressed,
              icon: isRefreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(isRefreshing
                  ? _t(context, 'generatingRecommendation')
                  : _t(context, 'newRecommendation')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.white,
                side: BorderSide(color: AppTheme.white.withOpacity(0.75)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        '${_t(context, 'updatedLabel')} ${_formatDate(recommendation.updatedAt)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.white,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: recommendation.completionPercentage / 100,
                      minHeight: 7,
                      backgroundColor: AppTheme.white.withOpacity(0.18),
                      valueColor:
                          const AlwaysStoppedAnimation(AppTheme.accentGreen),
                    ),
                  ],
                );
              }

              return Row(
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
                      '${_t(context, 'updatedLabel')} ${_formatDate(recommendation.updatedAt)}',
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
              );
            },
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
          final label = version.languageCode.toLowerCase().startsWith('am')
              ? _t(context, 'amharicLabel')
              : _t(context, 'englishLabel');
          return ChoiceChip(
            selected: isSelected,
            label: Text(label),
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
        border: Border.all(color: accent.withOpacity(0.22)),
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

  Widget _buildReportSummaryCard({
    required BuildContext context,
    required HealthRecommendation recommendation,
    required int sectionCount,
    required int itemCount,
    required String languageCode,
  }) {
    final languageLabel = languageCode.toLowerCase().startsWith('am')
        ? _t(context, 'amharicLabel')
        : _t(context, 'englishLabel');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.mediumGray),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _summaryPill(context, Icons.article_outlined,
              '$sectionCount ${_t(context, 'sections')}'),
          _summaryPill(context, Icons.checklist_rounded,
              '$itemCount ${_t(context, 'actionItems')}'),
          _summaryPill(
            context,
            Icons.language,
            languageLabel,
          ),
          _summaryPill(
            context,
            Icons.schedule,
            '${_t(context, 'updatedLabel')} ${_formatDate(recommendation.updatedAt)}',
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.lightGray,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.mediumGray),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryBlue),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.veryDarkGray,
                ),
          ),
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
    if (lower.contains('risk') || lower.contains('stratification')) {
      return AppTheme.accentOrange;
    }
    if (lower.contains('recommendation')) {
      return AppTheme.accentGreen;
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
    if (lower.contains('risk') || lower.contains('stratification')) {
      return Icons.warning_amber_rounded;
    }
    if (lower.contains('recommendation')) {
      return Icons.task_alt;
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

  int _contentItemCount(_ReportVersion report) {
    var count = 0;
    for (final section in report.sections) {
      count += section.paragraphs.length;
      count += section.bullets.length;
      count += section.numberedItems.length;
    }
    return count;
  }
}

class _SymptomOption {
  final String key;
  final String label;
  final IconData icon;
  final bool isHighRisk;
  final String qualityQuestion;
  final List<String> qualityOptions;

  const _SymptomOption({
    required this.key,
    required this.label,
    required this.icon,
    this.isHighRisk = false,
    required this.qualityQuestion,
    required this.qualityOptions,
  });
}

class _OpqrstAnswers {
  final String? onset;
  final String? quality;
  final double? severity;
  final String? timing;

  const _OpqrstAnswers({
    this.onset,
    this.quality,
    this.severity = 5,
    this.timing,
  });

  _OpqrstAnswers copyWith({
    String? onset,
    String? quality,
    double? severity,
    String? timing,
  }) {
    return _OpqrstAnswers(
      onset: onset ?? this.onset,
      quality: quality ?? this.quality,
      severity: severity ?? this.severity,
      timing: timing ?? this.timing,
    );
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

    bool isDisclaimerTitle(String title) {
      final lower = title.toLowerCase();
      return lower.contains('disclaimer') || lower.contains('ማሳሰቢያ');
    }

    void flushSection() {
      if (currentTitle == null) return;

      final cleanedTitle = _cleanText(currentTitle);
      final joined = buffer
          .map((line) => _cleanText(line))
          .where((line) => line.isNotEmpty)
          .join(' ')
          .trim();

      if (isDisclaimerTitle(cleanedTitle)) {
        if (joined.isNotEmpty) {
          disclaimer = joined;
        }
      } else {
        sections.add(_ReportSection.parse(cleanedTitle, buffer));
      }

      buffer.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final bracketHeader = RegExp(r'^\[(.+)\]$').firstMatch(trimmed);
      if (bracketHeader != null) {
        flushSection();
        currentTitle = _cleanText(bracketHeader.group(1) ?? '');
        continue;
      }

      if (trimmed.startsWith('###')) {
        flushSection();
        currentTitle = _cleanText(trimmed.replaceFirst('###', ''));
        continue;
      }

      if (trimmed.startsWith('##')) {
        flushSection();
        currentTitle = _cleanText(trimmed.replaceFirst('##', ''));
        continue;
      }

      if (trimmed.startsWith('#')) {
        flushSection();
        currentTitle = _cleanText(trimmed.replaceFirst('#', ''));
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

      if (line.startsWith('*') ||
          line.startsWith('-') ||
          line.startsWith('•')) {
        final value = _stripPrefix(
          line.replaceFirst(RegExp(r'^[*\-•]+\s*'), ''),
        );
        if (value.isNotEmpty) {
          bullets.add(value);
        }
        continue;
      }

      if (RegExp(r'^\d+\.\s+').hasMatch(line)) {
        final value = _stripPrefix(
          line.replaceFirst(RegExp(r'^\d+\.\s+'), ''),
        );
        if (value.isNotEmpty) {
          numbered.add(value);
        }
        continue;
      }

      final value = _stripPrefix(line);
      if (value.isNotEmpty) {
        paragraphs.add(value);
      }
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
