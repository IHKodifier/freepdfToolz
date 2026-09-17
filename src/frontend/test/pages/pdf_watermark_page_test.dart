import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_watermark_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_watermark_progress_page.dart';
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
    'PdfWatermarkPage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfWatermarkPage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Watermark PDF'), findsOneWidget);
      expect(
        find.textContaining(
          'Stamp custom text or transparent image watermarks across your document',
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
    'PdfWatermarkProgressPage renders overview, watermark controls, and live preview box',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'LegalContract.pdf',
        sizeBytes: 1024 * 350,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfWatermarkProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('LegalContract.pdf'), findsOneWidget);
      expect(find.textContaining('3 Pages'), findsOneWidget);
      expect(find.text('350.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify Mode Switcher tabs: Text Watermark vs Image Logo
      expect(find.text('Text Watermark'), findsOneWidget);
      expect(find.text('Image Logo'), findsOneWidget);

      // Verify Text Preset chips
      expect(find.text('CONFIDENTIAL'), findsWidgets);
      expect(find.text('DRAFT'), findsOneWidget);
      expect(find.text('DO NOT COPY'), findsOneWidget);
      expect(find.text('SAMPLE'), findsOneWidget);

      // Verify Angle chips (-45°, 0°, 45°)
      expect(find.byKey(const Key('angle_minus_45')), findsOneWidget);
      expect(find.byKey(const Key('angle_0')), findsOneWidget);
      expect(find.byKey(const Key('angle_45')), findsOneWidget);

      // Verify Opacity slider
      expect(find.textContaining('Opacity:'), findsOneWidget);

      // Verify Live Preview Box exists
      expect(find.byKey(const Key('live_preview_box')), findsOneWidget);

      // Verify Apply Watermark button
      expect(
        find.widgetWithText(ElevatedButton, 'Apply Watermark'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Typing custom text updates live preview text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(2);
    final mockFile = SelectedPdfFile(
      name: 'Document.pdf',
      sizeBytes: 1024 * 100,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfWatermarkProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Find custom text field and enter new text
    final customTextField = find.byKey(
      const Key('watermark_custom_text_field'),
    );
    expect(customTextField, findsOneWidget);

    await tester.enterText(customTextField, 'TOP SECRET');
    await tester.pumpAndSettle();

    // Verify live preview reflects the updated text
    final previewText = find.descendant(
      of: find.byKey(const Key('live_preview_box')),
      matching: find.text('TOP SECRET'),
    );
    expect(previewText, findsOneWidget);
  });

  testWidgets('Switching watermark type switches to image logo controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(1);
    final mockFile = SelectedPdfFile(
      name: 'SinglePage.pdf',
      sizeBytes: 1024 * 50,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfWatermarkProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Tap Image Logo tab
    final imageTab = find.text('Image Logo');
    await tester.tap(imageTab);
    await tester.pumpAndSettle();

    // Verify image picker button is visible
    expect(find.text('Select Logo Image (PNG / JPG)'), findsOneWidget);
  });
}
