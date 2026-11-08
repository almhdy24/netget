import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/settings_repository.dart';
import '../../services/analytics_service.dart';

Future<void> showFirstRunAnalyticsPrompt(
  BuildContext context,
  SettingsRepository repository,
) async {
  final settings = await repository.loadSettings();
  if (settings.analyticsPromptShown || !context.mounted) return;

  final theme = Theme.of(context);
  final isArabic = Directionality.of(context) == TextDirection.rtl;

  final choice = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(isArabic ? 'الخصوصية والتحليلات' : 'Privacy & Telemetry'),
        ],
      ),
      content: Text(
        isArabic
            ? 'تساعد إحصائيات الاستخدام المجهولة في تحسين ${NetGetConstants.appName} وإصلاح الأخطاء وسرعة التنزيل.\n\nلا نجمع أي روابط أو أسماء ملفات أو بيانات شخصية إطلاقاً.'
            : 'Anonymous usage statistics help us improve ${NetGetConstants.appName} and fix download performance issues.\n\nNo URLs, filenames, paths, or personal data are ever sent.',
        style: const TextStyle(fontSize: 12.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(isArabic ? 'تعطيل' : 'No thanks'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(80, 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Text(isArabic ? 'موافق وتفعيل' : 'Allow anonymous stats'),
        ),
      ],
    ),
  );

  final enabled = choice ?? false;
  final updated = settings.copyWith(
    analyticsPromptShown: true,
    analyticsEnabled: enabled,
  );
  await repository.saveSettings(updated);
  await AnalyticsService.setEnabled(enabled);
}
