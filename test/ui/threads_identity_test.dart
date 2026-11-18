import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/design_tokens.dart';
import 'package:netget/core/segment_planner.dart';
import 'package:netget/ui/widgets/budget_ring.dart';
import 'package:netget/ui/widgets/connection_pulse.dart';
import 'package:netget/ui/widgets/thread_bar.dart';
import 'package:netget/ui/widgets/thread_empty_state.dart';

void main() {
  group('«خيوط» (Threads) Visual Identity & Custom Painters', () {
    testWidgets('ThreadBar renders multi-segment strands correctly', (
      tester,
    ) async {
      final segments = [
        const DownloadSegment(
          index: 0,
          startByte: 0,
          endByte: 999,
          downloadedBytes: 1000,
          isCompleted: true,
        ),
        const DownloadSegment(
          index: 1,
          startByte: 1000,
          endByte: 1999,
          downloadedBytes: 500,
          isCompleted: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: ThreadBar(
                  segments: segments,
                  totalBytes: 2000,
                  downloadedBytes: 1500,
                  isDownloading: true,
                  height: 6.0,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ThreadBar), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets(
      'ThreadBar handles single-connection and indeterminate states',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ThreadBar(
                segments: [],
                totalBytes: 1000,
                downloadedBytes: 300,
              ),
            ),
          ),
        );
        expect(find.byType(ThreadBar), findsOneWidget);

        // Indeterminate total size
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ThreadBar(
                segments: [],
                totalBytes: -1,
                downloadedBytes: 500,
              ),
            ),
          ),
        );
        expect(find.byType(ThreadBar), findsOneWidget);
      },
    );

    testWidgets('ConnectionPulse toggles animation based on isActive', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ConnectionPulse(isActive: true, size: 12)),
        ),
      );

      expect(find.byType(ConnectionPulse), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ConnectionPulse(isActive: false, size: 12)),
        ),
      );
      expect(find.byType(ConnectionPulse), findsOneWidget);
    });

    testWidgets('BudgetRing paints concentric arcs with center summary', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BudgetRing(
              countedBytes: 3000,
              freeBytes: 2000,
              limitBytes: 10000,
              size: 120,
              centerChild: Text('50%'),
            ),
          ),
        ),
      );

      expect(find.byType(BudgetRing), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('ThreadEmptyState displays Arabic slogan and responds to tap', (
      tester,
    ) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ThreadEmptyState(
                onAddPressed: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('ما بنبدأ من الصفر'), findsOneWidget);
      expect(find.text('إضافة تحميل جديد'), findsOneWidget);

      await tester.tap(find.text('إضافة تحميل جديد'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    test('ThreadTokens returns consistent thread colors', () {
      final c0 = ThreadTokens.threadColor(0);
      final c1 = ThreadTokens.threadColor(1);
      final cWrap = ThreadTokens.threadColor(ThreadTokens.threadStrands.length);

      expect(c0, equals(ThreadTokens.desertAmber));
      expect(c1, equals(ThreadTokens.nileBlue));
      expect(cWrap, equals(c0));
    });
  });
}
