import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/settings_repository.dart';
import '../../services/analytics_service.dart';

/// Settings modal dialog providing theme configuration and privacy telemetry toggle.
class SettingsDialog extends StatefulWidget {
  final SettingsRepository settingsRepository;
  final ValueNotifier<ThemeMode> themeModeNotifier;

  const SettingsDialog({
    super.key,
    required this.settingsRepository,
    required this.themeModeNotifier,
  });

  static Future<void> show(
    BuildContext context, {
    SettingsRepository? settingsRepository,
    required ValueNotifier<ThemeMode> themeModeNotifier,
  }) {
    AnalyticsService.screenView('settings');
    return showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(
        settingsRepository: settingsRepository ?? SettingsRepository(),
        themeModeNotifier: themeModeNotifier,
      ),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _analyticsEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await widget.settingsRepository.loadAnalyticsEnabled();
    if (mounted) {
      setState(() {
        _analyticsEnabled = enabled;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleAnalytics(bool value) async {
    setState(() => _analyticsEnabled = value);
    await widget.settingsRepository.saveAnalyticsEnabled(value);
    await AnalyticsService.setEnabled(value);
    AnalyticsService.trackSettingChanged(
      settingName: 'analytics_enabled',
      settingValue: value.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings_rounded, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Text(isArabic ? 'الإعدادات' : 'Settings'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: _isLoading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Privacy & Analytics Telemetry
                  Text(
                    isArabic ? 'الخصوصية والتحليلات' : 'Privacy & Telemetry',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      isArabic ? 'إحصائيات الاستخدام المجهولة' : 'Anonymous usage statistics',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: Text(
                      isArabic
                          ? 'تساعد في تحسين التطبيق بإرسال مقاييس الأداء والأخطاء فقط. لا يتم إرسال روابط أو أسماء ملفات أو بيانات خاصة إطلاقاً.'
                          : 'Helps improve NetGet with anonymous crash and performance metrics. Zero URLs, filenames, or personal data are ever sent.',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                    value: _analyticsEnabled,
                    onChanged: _toggleAnalytics,
                  ),
                  const Divider(height: 24),

                  // Appearance Theme
                  Text(
                    isArabic ? 'المظهر والسمة' : 'Appearance',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: widget.themeModeNotifier,
                    builder: (context, currentMode, _) {
                      return SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: const Icon(Icons.brightness_auto_rounded, size: 16),
                            label: Text(isArabic ? 'تلقائي' : 'System', style: const TextStyle(fontSize: 12)),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: const Icon(Icons.light_mode_rounded, size: 16),
                            label: Text(isArabic ? 'فاتح' : 'Light', style: const TextStyle(fontSize: 12)),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: const Icon(Icons.dark_mode_rounded, size: 16),
                            label: Text(isArabic ? 'داكن' : 'Dark', style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                        selected: {currentMode},
                        onSelectionChanged: (selected) {
                          final newMode = selected.first;
                          widget.themeModeNotifier.value = newMode;
                          widget.settingsRepository.saveThemeMode(newMode);
                          AnalyticsService.trackSettingChanged(
                            settingName: 'theme_mode',
                            settingValue: newMode.name,
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Version label
                  Center(
                    child: Text(
                      '${NetGetConstants.appName} v${NetGetConstants.appVersion}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isArabic ? 'إغلاق' : 'Close'),
        ),
      ],
    );
  }
}
