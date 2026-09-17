import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_rotate_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_rotate_progress_page.dart';
import 'package:freepdftoolz_frontend/utils/app_limits_config.dart';
import 'package:freepdftoolz_frontend/widgets/adsense_banner.dart';

Uint8List createMockPdfBytesWithPages(int pageCount) {
  final content =
      '''
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [] /Count $pageCount >>
endobj
xref
0 3
0000000000 65535 f 
0000000010 00000 n 
0000000060 00000 n 
trailer
<< /Size 3 /Root 1 0 R >>
startxref
120
%%EOF
''';
  return Uint8List.fromList(content.codeUnits);
}

void main() {
  setUp(() {
    AppLimitsConfig.resetBoost();
  });

  testWidgets(
    'PdfRotatePage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfRotatePage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Rotate PDF'), findsOneWidget);
      expect(
        find.textContaining('Rotate individual pages or entire documents'),
        findsOneWidget,
      );

      // Verify Dropzone prompt & dynamic limits notice (no hardcoded limits)
      expect(find.textContaining('Drop PDF file here'), findsOneWidget);
      expect(find.text('Select PDF File'), findsOneWidget);
      expect(find.text(AppLimitsConfig.dropzoneNoticeText), findsOneWidget);

      // Verify AdSense Banner #1 on landing page
      expect(find.byType(AdSenseBanner), findsOneWidget);
    },
  );

  testWidgets(
    'PdfRotateProgressPage renders document overview, page thumbnail cards, toolbar, and rotate buttons',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'ScanReport.pdf',
        sizeBytes: 1024 * 300,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfRotateProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('ScanReport.pdf'), findsOneWidget);
      expect(find.textContaining('3 Pages'), findsOneWidget);
      expect(find.text('300.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify Toolbar buttons
      expect(find.text('Rotate All Right (+90°)'), findsOneWidget);
      expect(find.text('Rotate All Left (-90°)'), findsOneWidget);
      expect(find.text('Reset All'), findsOneWidget);

      // Verify Page cards
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Page 3'), findsOneWidget);

      // Initial degree badges
      expect(find.text('0°'), findsNWidgets(3));

      // Verify primary action button
      expect(
        find.widgetWithText(ElevatedButton, 'Save & Apply Rotation'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PdfRotateProgressPage updates rotation angle when card rotate buttons tapped',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(2);
      final mockFile = SelectedPdfFile(
        name: 'Document.pdf',
        sizeBytes: 1024 * 150,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfRotateProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Tap rotate right (+90°) on Page 1
      final rotateRightFinder = find.byKey(const Key('rotate_right_page_0'));
      expect(rotateRightFinder, findsOneWidget);
      await tester.tap(rotateRightFinder);
      await tester.pumpAndSettle();

      // Page 1 should now display 90°
      expect(find.text('90°'), findsOneWidget);

      // Tap rotate right again -> 180°
      await tester.tap(rotateRightFinder);
      await tester.pumpAndSettle();
      expect(find.text('180°'), findsOneWidget);

      // Tap rotate left on Page 1 -> 90°
      final rotateLeftFinder = find.byKey(const Key('rotate_left_page_0'));
      expect(rotateLeftFinder, findsOneWidget);
      await tester.tap(rotateLeftFinder);
      await tester.pumpAndSettle();
      expect(find.text('90°'), findsOneWidget);
    },
  );

  testWidgets(
    'PdfRotateProgressPage global toolbar rotates all pages and resets',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'Batch.pdf',
        sizeBytes: 1024 * 250,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfRotateProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Initially all 3 pages are at 0°
      expect(find.text('0°'), findsNWidgets(3));

      // Tap Rotate All Right
      await tester.tap(find.text('Rotate All Right (+90°)'));
      await tester.pumpAndSettle();

      // Now all 3 pages are at 90°
      expect(find.text('90°'), findsNWidgets(3));

      // Tap Reset All
      await tester.tap(find.text('Reset All'));
      await tester.pumpAndSettle();

      // All 3 pages back to 0°
      expect(find.text('0°'), findsNWidgets(3));
    },
  );
}
