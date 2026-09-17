import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_crop_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_crop_progress_page.dart';
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
    'PdfCropPage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfCropPage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Crop PDF'), findsOneWidget);
      expect(
        find.textContaining(
          'Trim page margins or select custom viewport boundaries for your PDF',
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
    'PdfCropProgressPage renders overview, margin controls, and live preview box',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'FinancialStatement.pdf',
        sizeBytes: 1024 * 420,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfCropProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('FinancialStatement.pdf'), findsOneWidget);
      expect(find.textContaining('3 Pages'), findsOneWidget);
      expect(find.text('420.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify Margin Presets
      expect(find.text('Zero Margins'), findsOneWidget);
      expect(find.text('Auto Trim 10%'), findsOneWidget);
      expect(find.text('Standard 0.5in (36pt)'), findsOneWidget);
      expect(find.text('Wide 1.0in (72pt)'), findsOneWidget);

      // Verify Margin Labels
      expect(find.text('Top Margin'), findsOneWidget);
      expect(find.text('Bottom Margin'), findsOneWidget);
      expect(find.text('Left Margin'), findsOneWidget);
      expect(find.text('Right Margin'), findsOneWidget);

      // Verify Scope Switch
      expect(find.text('Apply to all pages'), findsOneWidget);

      // Verify Action button
      expect(find.text('Crop PDF'), findsOneWidget);
    },
  );

  testWidgets('Selecting crop preset chips updates margin inputs', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(1);
    final mockFile = SelectedPdfFile(
      name: 'Receipt.pdf',
      sizeBytes: 1024 * 50,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfCropProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Tap Standard 0.5in (36pt) preset
    final standardPreset = find.text('Standard 0.5in (36pt)');
    expect(standardPreset, findsOneWidget);
    await tester.tap(standardPreset);
    await tester.pumpAndSettle();

    // Value indicators should now show 36 pt
    expect(find.text('36 pt'), findsWidgets);
  });

  testWidgets('Toggling apply to all pages switches scope state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(2);
    final mockFile = SelectedPdfFile(
      name: 'BookPages.pdf',
      sizeBytes: 1024 * 100,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfCropProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Verify switch is present
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);

    // Toggle switch off
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Verify page target selector appears when apply to all pages is turned off
    expect(find.textContaining('Page 1 of 2'), findsOneWidget);
  });
}
