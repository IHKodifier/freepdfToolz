import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_extract_pages_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_extract_pages_progress_page.dart';
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
    'PdfExtractPagesPage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfExtractPagesPage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Extract PDF Pages'), findsOneWidget);
      expect(
        find.textContaining('Select specific pages to extract'),
        findsOneWidget,
      );

      // Verify Dropzone prompt & dynamic limits notice
      expect(find.textContaining('Drop PDF file here'), findsOneWidget);
      expect(find.text('Select PDF File'), findsOneWidget);
      expect(find.text(AppLimitsConfig.dropzoneNoticeText), findsOneWidget);

      // Verify AdSense Banner #1 on landing page
      expect(find.byType(AdSenseBanner), findsOneWidget);
    },
  );

  testWidgets(
    'PdfExtractPagesProgressPage renders document overview, page selector, quick actions, and extract button',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(4);
      final mockFile = SelectedPdfFile(
        name: 'SampleHandbook.pdf',
        sizeBytes: 1024 * 500,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfExtractPagesProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('SampleHandbook.pdf'), findsOneWidget);
      expect(find.textContaining('4 Pages'), findsOneWidget);
      expect(find.text('500.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify Quick Action buttons
      expect(find.text('Select All'), findsOneWidget);
      expect(find.text('Deselect All'), findsOneWidget);
      expect(find.text('Even Pages'), findsOneWidget);
      expect(find.text('Odd Pages'), findsOneWidget);

      // Verify Mode Selector
      expect(find.textContaining('Merge into one PDF'), findsOneWidget);
      expect(find.textContaining('Separate PDFs (ZIP)'), findsOneWidget);

      // Verify Page cards
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Page 3'), findsOneWidget);
      expect(find.text('Page 4'), findsOneWidget);

      // Verify Extract Pages button
      expect(
        find.widgetWithText(ElevatedButton, 'Extract Pages'),
        findsOneWidget,
      );
    },
  );

  testWidgets('PdfExtractPagesProgressPage quick select buttons work', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(4);
    final mockFile = SelectedPdfFile(
      name: 'MultiPage.pdf',
      sizeBytes: 1024 * 200,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfExtractPagesProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Tap "Even Pages"
    await tester.tap(find.text('Even Pages'));
    await tester.pumpAndSettle();

    // Pages 2 and 4 should be selected (2 of 4 selected)
    expect(find.textContaining('2 of 4 pages selected'), findsOneWidget);

    // Tap "Deselect All"
    await tester.tap(find.text('Deselect All'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 of 4 pages selected'), findsOneWidget);

    // Tap "Odd Pages"
    await tester.tap(find.text('Odd Pages'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 of 4 pages selected'), findsOneWidget);

    // Tap "Select All"
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 of 4 pages selected'), findsOneWidget);
  });

  testWidgets(
    'PdfExtractPagesProgressPage toggling card selects/deselects page',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'CardToggle.pdf',
        sizeBytes: 1024 * 100,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfExtractPagesProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Tap card for Page 1 (index 0)
      final page1Card = find.byKey(const Key('page_card_0'));
      expect(page1Card, findsOneWidget);
      await tester.tap(page1Card);
      await tester.pumpAndSettle();

      // Verify 1 page selected
      expect(find.textContaining('1 of 3 pages selected'), findsOneWidget);

      // Tap again to deselect
      await tester.tap(page1Card);
      await tester.pumpAndSettle();

      expect(find.textContaining('0 of 3 pages selected'), findsOneWidget);
    },
  );
}
