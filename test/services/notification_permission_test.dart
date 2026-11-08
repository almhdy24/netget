import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/services/notification_permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.elmahdi.netget/engine');
  late List<MethodCall> methodCalls;
  String mockPermissionResult = 'granted';
  String mockCheckResult = 'denied';

  setUp(() {
    methodCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          methodCalls.add(call);
          switch (call.method) {
            case 'checkNotificationPermission':
              return mockCheckResult;
            case 'requestNotificationPermission':
              return mockPermissionResult;
            case 'openNotificationSettings':
              return true;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('NotificationPermissionService - Native MethodChannel Tests', () {
    test(
      'checkPermission returns granted when native returns granted (API < 33 or enabled)',
      () async {
        // On API < 33 notifications are granted by default unless disabled in system settings (verify in docs)
        mockCheckResult = 'granted';
        final service = NotificationPermissionService(channel: channel);

        final status = await service.checkPermission();
        expect(status, equals(NotificationPermissionStatus.granted));
        expect(service.shouldShowHomeBanner, isFalse);
        expect(
          methodCalls.map((c) => c.method),
          contains('checkNotificationPermission'),
        );
      },
    );

    test(
      'checkPermission returns denied when notifications are disabled',
      () async {
        mockCheckResult = 'denied';
        final service = NotificationPermissionService(channel: channel);

        final status = await service.checkPermission();
        expect(status, equals(NotificationPermissionStatus.denied));
        expect(service.shouldShowHomeBanner, isTrue);
      },
    );

    test(
      'requestPermission returns granted when user accepts system dialog',
      () async {
        mockPermissionResult = 'granted';
        final service = NotificationPermissionService(channel: channel);

        final status = await service.requestPermission();
        expect(status, equals(NotificationPermissionStatus.granted));
        expect(service.shouldShowHomeBanner, isFalse);
        expect(
          methodCalls.map((c) => c.method),
          contains('requestNotificationPermission'),
        );
      },
    );

    test(
      'requestPermission returns denied when user rejects system dialog once',
      () async {
        mockPermissionResult = 'denied';
        final service = NotificationPermissionService(channel: channel);

        final status = await service.requestPermission();
        expect(status, equals(NotificationPermissionStatus.denied));
        expect(service.shouldShowHomeBanner, isTrue);
      },
    );

    test(
      'requestPermission returns permanentlyDenied when user selects Do not ask again',
      () async {
        // On Android 13+, when shouldShowRequestPermissionRationale is false upon denial, permission is permanently denied (verify in docs)
        mockPermissionResult = 'permanently_denied';
        final service = NotificationPermissionService(channel: channel);

        final status = await service.requestPermission();
        expect(status, equals(NotificationPermissionStatus.permanentlyDenied));
        expect(service.shouldShowHomeBanner, isTrue);
      },
    );

    test(
      'openSettings invokes openNotificationSettings on native engine',
      () async {
        final service = NotificationPermissionService(channel: channel);
        await service.openSettings();
        expect(
          methodCalls.map((c) => c.method),
          contains('openNotificationSettings'),
        );
      },
    );

    test(
      'dismissBanner hides the banner for the rest of the session',
      () async {
        mockCheckResult = 'denied';
        final service = NotificationPermissionService(channel: channel);
        await service.checkPermission();
        expect(service.shouldShowHomeBanner, isTrue);

        service.dismissBanner();
        expect(service.bannerDismissed, isTrue);
        expect(service.shouldShowHomeBanner, isFalse);

        service.resetSession();
        expect(service.bannerDismissed, isFalse);
        expect(service.shouldShowHomeBanner, isTrue);
      },
    );
  });

  group('In-Context Prompt Flow & Session Nagging Tests', () {
    testWidgets(
      'maybePromptForDownload shows explanation sheet on first download and prompts system',
      (WidgetTester tester) async {
        mockCheckResult = 'denied';
        mockPermissionResult = 'granted';

        final service = NotificationPermissionService(channel: channel);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => service.maybePromptForDownload(context),
                    child: const Text('Start Download'),
                  ),
                ),
              ),
            ),
          ),
        );

        // Tap to trigger in-context download prompt
        await tester.tap(find.text('Start Download'));
        await tester.pumpAndSettle();

        // Verify explanation sheet is shown with required copy
        expect(
          find.text(
            'Notifications show download progress and let downloads continue in the background.',
          ),
          findsOneWidget,
        );

        // Tap 'Continue' to trigger system permission dialog
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(
          methodCalls.map((c) => c.method),
          contains('requestNotificationPermission'),
        );
        expect(service.hasPromptedThisSession, isTrue);

        // Verify that starting another download does NOT nag the user again in the same session
        methodCalls.clear();
        await tester.tap(find.text('Start Download'));
        await tester.pumpAndSettle();

        // Explanation sheet is NOT shown again
        expect(
          find.text(
            'Notifications show download progress and let downloads continue in the background.',
          ),
          findsNothing,
        );
        expect(methodCalls, isEmpty);
      },
    );
  });
}
