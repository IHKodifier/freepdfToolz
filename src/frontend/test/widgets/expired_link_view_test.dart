import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/widgets/expired_link_view.dart';

void main() {
  group('ExpiredLinkView Widget Tests', () {
    testWidgets(
      'renders download link expired title and local timezone message',
      (WidgetTester tester) async {
        final testDate = DateTime.utc(2026, 8, 27, 14, 30, 0);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ExpiredLinkView(expiredAt: testDate)),
          ),
        );

        expect(find.text('Download Link Expired'), findsOneWidget);
        expect(find.byIcon(Icons.timer_off_rounded), findsOneWidget);
        expect(
          find.textContaining('This download link expired on'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Output files are purged after 24h for privacy.'),
          findsOneWidget,
        );
        expect(find.text('Upload New Document'), findsOneWidget);
      },
    );

    testWidgets('triggers onUploadNew callback when button is clicked', (
      WidgetTester tester,
    ) async {
      bool buttonPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExpiredLinkView(
              rawExpiredAtString: '2026-08-27T14:30:00Z',
              onUploadNew: () {
                buttonPressed = true;
              },
            ),
          ),
        ),
      );

      final buttonFinder = find.byKey(const Key('upload_new_document_button'));
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(buttonPressed, isTrue);
    });
  });
}
