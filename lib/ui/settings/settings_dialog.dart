import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/settings_repository.dart';
import '../../models/app_settings.dart';
import '../../services/analytics_service.dart';

/// Desktop-style Preferences / Settings dialog.
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
  AppSettings _settings = const AppSettings();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await widget.settingsRepository.loadSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateSettings(AppSettings updated) async {
    setState(() => _settings = updated);
    await widget.settingsRepository.saveSettings(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.tune, color: colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Text(isArabic ? 'الإعدادات' : 'Preferences'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      content: SizedBox(
        width: 480,
        child: _isLoading
            ? const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- DOWNLOAD ENGINE ---
                    _buildSectionHeader('DOWNLOADS', colorScheme),
                    const SizedBox(height: 8),
                    _buildDropdownRow<int>(
                      label: isArabic
                          ? 'التحميلات المتزامنة القصوى'
                          : 'Max concurrent downloads',
                      value: _settings.maxConcurrent,
                      items: const [1, 2, 3, 4, 5],
                      itemLabel: (v) => '$v',
                      onChanged: (val) {
                        if (val != null) {
                          _updateSettings(
                            _settings.copyWith(maxConcurrent: val),
                          );
                          AnalyticsService.trackSettingChanged(
                            settingName: 'max_concurrent',
                            settingValue: '$val',
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildDropdownRow<int>(
                      label: isArabic
                          ? 'أجزاء الاتصال لكل تحميل'
                          : 'Connections per download',
                      value: _settings.connectionsPerDownload,
                      items: const [1, 2, 4, 8],
                      itemLabel: (v) => '$v parts',
                      onChanged: (val) {
                        if (val != null) {
                          _updateSettings(
                            _settings.copyWith(connectionsPerDownload: val),
                          );
                          AnalyticsService.trackSettingChanged(
                            settingName: 'connections_per_download',
                            settingValue: '$val',
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isArabic
                            ? 'التحميل عبر واي-فاي فقط'
                            : 'Download over Wi-Fi only',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      value: _settings.wifiOnly,
                      onChanged: (val) {
                        _updateSettings(_settings.copyWith(wifiOnly: val));
                        AnalyticsService.trackSettingChanged(
                          settingName: 'wifi_only',
                          settingValue: '$val',
                        );
                      },
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isArabic
                            ? 'أصوات إشعار الاكتمال'
                            : 'Completion sound effects',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      value: _settings.soundsEnabled,
                      onChanged: (val) {
                        _updateSettings(_settings.copyWith(soundsEnabled: val));
                        AnalyticsService.trackSettingChanged(
                          settingName: 'sounds_enabled',
                          settingValue: '$val',
                        );
                      },
                    ),

                    const Divider(height: 20),

                    // --- APPEARANCE ---
                    _buildSectionHeader('APPEARANCE', colorScheme),
                    const SizedBox(height: 8),
                    SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: const Icon(Icons.brightness_auto, size: 14),
                          label: Text(
                            isArabic ? 'تلقائي' : 'System',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: const Icon(Icons.light_mode, size: 14),
                          label: Text(
                            isArabic ? 'فاتح' : 'Light',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: const Icon(Icons.dark_mode, size: 14),
                          label: Text(
                            isArabic ? 'داكن' : 'Dark',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ],
                      selected: {_settings.themeMode},
                      onSelectionChanged: (selected) {
                        final mode = selected.first;
                        widget.themeModeNotifier.value = mode;
                        _updateSettings(_settings.copyWith(themeMode: mode));
                        AnalyticsService.trackSettingChanged(
                          settingName: 'theme_mode',
                          settingValue: mode.name,
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildDropdownRow<String>(
                      label: isArabic ? 'اللغة' : 'Language',
                      value: _settings.language,
                      items: const ['system', 'en', 'ar'],
                      itemLabel: (v) {
                        switch (v) {
                          case 'ar':
                            return 'العربية';
                          case 'en':
                            return 'English';
                          default:
                            return isArabic ? 'تلقائي' : 'System default';
                        }
                      },
                      onChanged: (val) {
                        if (val != null) {
                          _updateSettings(_settings.copyWith(language: val));
                          AnalyticsService.trackSettingChanged(
                            settingName: 'language',
                            settingValue: val,
                          );
                        }
                      },
                    ),

                    const Divider(height: 20),

                    // --- PRIVACY & TELEMETRY ---
                    _buildSectionHeader('PRIVACY', colorScheme),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isArabic
                            ? 'إحصائيات الاستخدام المجهولة'
                            : 'Anonymous usage statistics',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        isArabic
                            ? 'تساعد في تحسين التطبيق بإرسال مقاييس الأداء والأخطاء فقط. لا يتم إرسال روابط أو أسماء ملفات أو بيانات خاصة إطلاقاً.'
                            : 'Shares anonymous crash and performance metrics to improve NetGet. URLs, filenames, and personal info are never collected.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                        ),
                      ),
                      value: _settings.analyticsEnabled,
                      onChanged: (val) async {
                        await _updateSettings(
                          _settings.copyWith(analyticsEnabled: val),
                        );
                        await AnalyticsService.setEnabled(val);
                        AnalyticsService.trackSettingChanged(
                          settingName: 'analytics_enabled',
                          settingValue: '$val',
                        );
                      },
                    ),

                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        '${NetGetConstants.appName} v${NetGetConstants.appVersion}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(80, 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Text(isArabic ? 'إغلاق' : 'Close'),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildDropdownRow<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
        DropdownButton<T>(
          value: value,
          isDense: true,
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    itemLabel(item),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
