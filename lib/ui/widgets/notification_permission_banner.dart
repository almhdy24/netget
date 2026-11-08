import 'package:flutter/material.dart';
import '../../services/notification_permission_service.dart';

class NotificationPermissionBanner extends StatelessWidget {
  final NotificationPermissionService permissionService;

  const NotificationPermissionBanner({
    super.key,
    required this.permissionService,
  });

  @override
  Widget build(BuildContext context) {
    if (!permissionService.shouldShowHomeBanner) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isArabic
                  ? 'يرجى تفعيل إذن الإشعارات لتتبع التحميلات في الخلفية'
                  : 'Enable notification permission to track downloads in background',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => permissionService.openSettings(),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              isArabic ? 'تفعيل' : 'Enable',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            tooltip: isArabic ? 'إغلاق' : 'Dismiss',
            onPressed: () => permissionService.dismissBanner(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }
}
