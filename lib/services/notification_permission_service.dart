import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents Android POST_NOTIFICATIONS permission status (Android 13+ / API 33+).
/// On Android < 33, notifications do not require runtime permission (verify in docs).
enum NotificationPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  notDetermined;

  bool get isGranted => this == NotificationPermissionStatus.granted;
}

class NotificationPermissionService extends ChangeNotifier {
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.elmahdi.netget/engine',
  );

  final MethodChannel channel;

  bool _hasPromptedThisSession = false;
  bool _bannerDismissed = false;
  NotificationPermissionStatus _status =
      NotificationPermissionStatus.notDetermined;

  NotificationPermissionService({MethodChannel? channel})
    : channel = channel ?? _defaultChannel;

  bool get hasPromptedThisSession => _hasPromptedThisSession;
  bool get bannerDismissed => _bannerDismissed;
  NotificationPermissionStatus get status => _status;

  /// Visible dismissible banner shown on Home when notifications are disabled.
  bool get shouldShowHomeBanner =>
      !_bannerDismissed &&
      (_status == NotificationPermissionStatus.denied ||
          _status == NotificationPermissionStatus.permanentlyDenied);

  void dismissBanner() {
    _bannerDismissed = true;
    notifyListeners();
  }

  void resetSession() {
    _hasPromptedThisSession = false;
    _bannerDismissed = false;
    notifyListeners();
  }

  /// Checks current notification permission without prompting the user.
  Future<NotificationPermissionStatus> checkPermission() async {
    try {
      final res = await channel.invokeMethod<String>(
        'checkNotificationPermission',
      );
      _status = _parseStatus(res);
    } catch (e) {
      debugPrint('checkNotificationPermission error: $e');
      _status = NotificationPermissionStatus.notDetermined;
    }
    notifyListeners();
    return _status;
  }

  /// Requests the POST_NOTIFICATIONS runtime permission natively via MainActivity.
  /// (Android 13+ / API 33+; verify in docs).
  Future<NotificationPermissionStatus> requestPermission() async {
    try {
      final res = await channel.invokeMethod<String>(
        'requestNotificationPermission',
      );
      _status = _parseStatus(res);
    } catch (e) {
      debugPrint('requestNotificationPermission error: $e');
      _status = NotificationPermissionStatus.denied;
    }
    notifyListeners();
    return _status;
  }

  /// Opens application notification settings directly.
  Future<void> openSettings() async {
    try {
      await channel.invokeMethod('openNotificationSettings');
    } catch (e) {
      debugPrint('openNotificationSettings error: $e');
    }
  }

  NotificationPermissionStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'granted':
        return NotificationPermissionStatus.granted;
      case 'permanently_denied':
        return NotificationPermissionStatus.permanentlyDenied;
      case 'denied':
        return NotificationPermissionStatus.denied;
      default:
        return NotificationPermissionStatus.notDetermined;
    }
  }

  /// In-context prompt flow:
  /// When the user starts their first download, show a short explanation sheet
  /// ("Notifications show download progress and let downloads continue in the background"),
  /// then trigger the native system dialog.
  /// Remembers choice and nags at most once per session.
  Future<void> maybePromptForDownload(BuildContext context) async {
    if (_hasPromptedThisSession) return;

    await checkPermission();
    if (_status == NotificationPermissionStatus.granted) return;

    _hasPromptedThisSession = true;

    if (!context.mounted) return;

    // If already permanently denied, do not show sheet; Home banner handles it.
    if (_status == NotificationPermissionStatus.permanentlyDenied) {
      notifyListeners();
      return;
    }

    final proceed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final isArabic = Directionality.of(ctx) == TextDirection.rtl;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.notifications_active_outlined,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isArabic ? 'إشعارات التنزيل' : 'Download Notifications',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  isArabic
                      ? 'تُظهر الإشعارات تقدم التنزيل وتتيح استمرار التنزيلات في الخلفية.'
                      : 'Notifications show download progress and let downloads continue in the background.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Theme.of(
                      ctx,
                    ).colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(isArabic ? 'ليس الآن' : 'Not now'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(isArabic ? 'متابعة' : 'Continue'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (proceed == true) {
      final newStatus = await requestPermission();
      if (newStatus == NotificationPermissionStatus.permanentlyDenied) {
        if (context.mounted) {
          final isArabic = Directionality.of(context) == TextDirection.rtl;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isArabic
                    ? 'تم رفض الإشعارات. يمكنك تفعيلها من الإعدادات.'
                    : 'Notifications are disabled. Enable them in Settings.',
              ),
              action: SnackBarAction(
                label: isArabic ? 'الإعدادات' : 'Settings',
                onPressed: openSettings,
              ),
            ),
          );
        }
      }
    }
  }
}
