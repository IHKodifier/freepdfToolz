import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_progress_page.dart';
import 'package:freepdftoolz_frontend/utils/app_limits_config.dart';
import 'package:freepdftoolz_frontend/widgets/adsense_banner.dart';

void main() {
  setUp(() {
    AppLimitsConfig.resetBoost();
  });

  testWidgets(
    'PdfMergePage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfMergePage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Merge PDF Files'), findsOneWidget);
      expect(
        find.textContaining('Combine multiple PDFs into a single document'),
        findsOneWidget,
      );

      // Verify Dropzone prompt & dynamic limits notice (no hardcoding)
      expect(find.textContaining('Drop PDF files here'), findsOneWidget);
      expect(find.text('Select PDF Files'), findsOneWidget);
      expect(find.text(AppLimitsConfig.dropzoneNoticeText), findsOneWidget);

      // Verify AdSense Banner #1 on landing page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify initial button state (disabled when 0 files)
      final mergeButtonFinder = find.widgetWithText(
        ElevatedButton,
        'Merge PDFs',
      );
      expect(mergeButtonFinder, findsOneWidget);
      final ElevatedButton mergeButton = tester.widget(mergeButtonFinder);
      expect(mergeButton.onPressed, isNull);
    },
  );

  testWidgets(
    'PdfMergePage renders added files in reorderable list and enables action',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: PdfMergePage(
            initialFiles: const [
              SelectedPdfFile(name: 'DocA.pdf', sizeBytes: 1024 * 1024),
              SelectedPdfFile(name: 'DocB.pdf', sizeBytes: 2 * 1024 * 1024),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify file names render
      expect(find.text('DocA.pdf'), findsOneWidget);
      expect(find.text('DocB.pdf'), findsOneWidget);

      // Verify file count & total size badge
      expect(find.textContaining('2 files selected'), findsOneWidget);

      // Verify merge button is enabled when >= 2 files
      final mergeButtonFinder = find.widgetWithText(
        ElevatedButton,
        'Merge PDFs (2)',
      );
      expect(mergeButtonFinder, findsOneWidget);
      final ElevatedButton mergeButton = tester.widget(mergeButtonFinder);
      expect(mergeButton.onPressed, isNotNull);

      // Verify delete button is present for each file
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    },
  );

  testWidgets(
    'PdfMergeProgressPage renders AdSense banner, file manager, and action button',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: PdfMergeProgressPage(
            initialFiles: [
              SelectedPdfFile(name: 'Report1.pdf', sizeBytes: 1024 * 1024),
              SelectedPdfFile(name: 'Report2.pdf', sizeBytes: 2 * 1024 * 1024),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header status and AdSense Banner #2 on progress page
      expect(find.text('Merging PDF Files'), findsOneWidget);
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify staged files list
      expect(find.text('Report1.pdf'), findsOneWidget);
      expect(find.text('Report2.pdf'), findsOneWidget);
      expect(find.textContaining('2 files selected'), findsOneWidget);

      // Verify action button is enabled and ready to merge
      final actionButtonFinder = find.widgetWithText(
        ElevatedButton,
        'Merge 2 PDFs',
      );
      expect(actionButtonFinder, findsOneWidget);
      final ElevatedButton actionButton = tester.widget(actionButtonFinder);
      expect(actionButton.onPressed, isNotNull);

      // Delete one file and verify button updates
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(find.text('Report1.pdf'), findsNothing);
      expect(find.text('Report2.pdf'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Add at least 2 files to merge'),
        findsOneWidget,
      );
    },
  );
}
