import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/utils.dart';
import 'package:netget/l10n/generated/app_localizations.dart';

void main() {
  group('Arabic-First RTL Localization Audit', () {
    testWidgets('loads Arabic localizations with RTL and core keys', (
      tester,
    ) async {
      late AppLocalizations l10n;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ar'),
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context)!;
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(body: Text(l10n.sloganNeverStartFromZero)),
              );
            },
          ),
        ),
      );

      expect(l10n.localeName, equals('ar'));
      expect(l10n.sloganNeverStartFromZero, equals('ما بنبدأ من الصفر'));
      expect(l10n.dataBudget, equals('ميزانية البيانات'));
      expect(l10n.nearbyShare, equals('شارك بالقرب'));
      expect(l10n.threads, equals('خيوط التحميل'));
      expect(find.text('ما بنبدأ من الصفر'), findsOneWidget);
    });

    testWidgets('loads English fallback localizations cleanly', (tester) async {
      late AppLocalizations l10n;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context)!;
              return Scaffold(body: Text(l10n.sloganNeverStartFromZero));
            },
          ),
        ),
      );

      expect(l10n.localeName, equals('en'));
      expect(l10n.sloganNeverStartFromZero, equals('We never start from zero'));
      expect(l10n.dataBudget, equals('Data Budget'));
      expect(l10n.threads, equals('Download Threads'));
      expect(find.text('We never start from zero'), findsOneWidget);
    });

    test('Eastern and Western Arabic digit formatting', () {
      expect(
        NetGetUtils.formatNumber(12345, easternDigits: false),
        equals('12345'),
      );
      expect(
        NetGetUtils.formatNumber(12345, easternDigits: true),
        equals('١٢٣٤٥'),
      );
      expect(NetGetUtils.formatNumber(0, easternDigits: true), equals('٠'));
    });
  });
}
