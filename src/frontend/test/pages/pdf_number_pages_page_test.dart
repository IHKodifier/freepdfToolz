import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_number_pages_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_number_pages_progress_page.dart';
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
    'PdfNumberPagesPage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfNumberPagesPage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Number PDF Pages'), findsOneWidget);
      expect(
        find.textContaining(
          'Add clean, customizable page numbers to your PDF documents',
        ),
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
    'PdfNumberPagesProgressPage renders overview, position matrix, format options, and live preview',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(5);
      final mockFile = SelectedPdfFile(
        name: 'QuarterlyReport.pdf',
        sizeBytes: 1024 * 400,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfNumberPagesProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('QuarterlyReport.pdf'), findsOneWidget);
      expect(find.textContaining('5 Pages'), findsOneWidget);
      expect(find.text('400.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify 3x3 Position Grid anchors
      expect(find.byKey(const Key('pos_top-left')), findsOneWidget);
      expect(find.byKey(const Key('pos_top-center')), findsOneWidget);
      expect(find.byKey(const Key('pos_top-right')), findsOneWidget);
      expect(find.byKey(const Key('pos_bottom-left')), findsOneWidget);
      expect(find.byKey(const Key('pos_bottom-center')), findsOneWidget);
      expect(find.byKey(const Key('pos_bottom-right')), findsOneWidget);

      // Verify Format options
      expect(find.text('Page {n} of {total}'), findsOneWidget);
      expect(find.text('{n}'), findsOneWidget);
      expect(find.text('Page {n}'), findsOneWidget);

      // Verify Skip Cover Page toggle
      expect(find.text('Skip First Page / Cover Page'), findsOneWidget);

      // Verify Live Preview Box exists
      expect(find.byKey(const Key('live_preview_box')), findsOneWidget);

      // Verify Apply Page Numbers button
      expect(
        find.widgetWithText(ElevatedButton, 'Apply Page Numbers'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Position grid selection updates active position and preview state',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'Document.pdf',
        sizeBytes: 1024 * 150,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfNumberPagesProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Default position is bottom-center
      final topRightAnchor = find.byKey(const Key('pos_top-right'));
      expect(topRightAnchor, findsOneWidget);

      // Tap top-right anchor
      await tester.tap(topRightAnchor);
      await tester.pumpAndSettle();

      // Verify preview box reflects top-right alignment
      final previewAlign = tester.widget<Align>(
        find.descendant(
          of: find.byKey(const Key('live_preview_box')),
          matching: find.byType(Align),
        ),
      );
      expect(previewAlign.alignment, Alignment.topRight);
    },
  );

  testWidgets('Format selector updates live preview text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(4);
    final mockFile = SelectedPdfFile(
      name: 'Thesis.pdf',
      sizeBytes: 1024 * 300,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfNumberPagesProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Initial default preview text
    expect(find.text('Page 1 of 4'), findsWidgets);

    // Tap '{n}' format choice
    await tester.tap(find.text('{n}'));
    await tester.pumpAndSettle();

    // Live preview text should now show just '1'
    final previewText = find.descendant(
      of: find.byKey(const Key('live_preview_box')),
      matching: find.text('1'),
    );
    expect(previewText, findsOneWidget);
  });
}
