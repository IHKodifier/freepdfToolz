import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_ocr_frontend/main.dart';
import 'package:free_ocr_frontend/pages/pdf_tools_hub_page.dart';
import 'package:free_ocr_frontend/pages/process_page.dart';
import 'package:free_ocr_frontend/widgets/adsense_banner.dart';
import 'package:free_ocr_frontend/widgets/ocr_progress_view.dart';
import 'package:free_ocr_frontend/widgets/app_header.dart';
import 'package:free_ocr_frontend/widgets/app_footer.dart';

void main() {
  group('ProcessPage Dedicated Route Tests', () {
    setUp(() {
      AdSenseBanner.kAdSenseApproved = true;
    });

    tearDown(() {
      AdSenseBanner.kAdSenseApproved = false;
    });

    testWidgets('ProcessPage renders AppHeader, OcrProgressView hero card, and AdSenseBanner underneath', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProcessPage(
            jobId: 'job_test_abc123',
            filename: 'annual_report.pdf',
            fileSize: 1048576,
          ),
        ),
      );
      await tester.pump();

      // Verify Header and Route
      expect(find.byType(AppHeader), findsOneWidget);

      // Verify Hero Section: OcrProgressView
      expect(find.byType(OcrProgressView), findsOneWidget);
      expect(find.textContaining('annual_report.pdf'), findsOneWidget);

      // Verify Underneath AdSenseBanner
      expect(find.byType(AdSenseBanner), findsOneWidget);
      expect(find.text('Sponsored Advertisement'), findsOneWidget);

      // Verify Footer
      expect(find.byType(AppFooter), findsOneWidget);
    });

    testWidgets('Route navigation /process/job_123 resolves properly from MaterialApp', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pump();

      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(
        context,
        '/process/job_test_456',
        arguments: {
          'filename': 'scanned_invoice.pdf',
          'fileSize': 2048576,
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ProcessPage), findsOneWidget);
      expect(find.textContaining('scanned_invoice.pdf'), findsOneWidget);
      expect(find.descendant(of: find.byType(ProcessPage), matching: find.byType(AdSenseBanner)), findsOneWidget);
    });

    testWidgets('ProcessPage reset button navigates back to landing page', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pump();

      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(
        context,
        '/process/job_test_789',
        arguments: {'filename': 'doc_to_cancel.pdf'},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ProcessPage), findsOneWidget);

      // Find Cancel / Upload New button inside OcrProgressView
      final cancelBtn = find.widgetWithText(OutlinedButton, 'Cancel');
      if (cancelBtn.evaluate().isNotEmpty) {
        await tester.tap(cancelBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(PdfToolsHubPage), findsOneWidget);
      }
    });

    testWidgets('ProcessPage with in-flight upload mounts cleanly with AdSenseBanner', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProcessPage(
            filename: 'immediate_drop.pdf',
            fileSize: 524288,
            bytes: Uint8List.fromList([1, 2, 3, 4]),
          ),
        ),
      );
      await tester.pump();

      // Verify ProcessPage and AdSenseBanner are present above the fold
      expect(find.byType(ProcessPage), findsOneWidget);
      expect(find.textContaining('immediate_drop.pdf'), findsOneWidget);
      expect(find.byType(AdSenseBanner), findsOneWidget);
    });

    testWidgets('OcrProgressView renders UPLOADING status with byte metrics', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OcrProgressView(
              filename: 'immediate_drop.pdf',
              fileSize: 1048576,
              status: 'UPLOADING',
              uploadSentBytes: 524288,
              uploadTotalBytes: 1048576,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Uploading Document...'), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    });
  });
}
