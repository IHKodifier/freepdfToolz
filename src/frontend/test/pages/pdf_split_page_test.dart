import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_split_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_split_progress_page.dart';
import 'package:freepdftoolz_frontend/utils/app_limits_config.dart';
import 'package:freepdftoolz_frontend/widgets/adsense_banner.dart';

Uint8List createMockPdfBytesWithPages(int pageCount) {
  // Minimal PDF header and trailer containing /Count X to simulate page detection
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
    'PdfSplitPage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfSplitPage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Split PDF'), findsOneWidget);
      expect(
        find.textContaining('Separate one page or an entire set of pages'),
        findsOneWidget,
      );

      // Verify Dropzone prompt & dynamic limits notice (no hardcoded copy)
      expect(find.textContaining('Drop PDF file here'), findsOneWidget);
      expect(find.text('Select PDF File'), findsOneWidget);
      expect(find.text(AppLimitsConfig.dropzoneNoticeText), findsOneWidget);

      // Verify AdSense Banner #1 on landing page
      expect(find.byType(AdSenseBanner), findsOneWidget);
    },
  );

  testWidgets(
    'PdfSplitProgressPage renders document overview, mode options, and split action',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(6);
      final mockFile = SelectedPdfFile(
        name: 'QuarterlyReport.pdf',
        sizeBytes: 1024 * 512,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfSplitProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('QuarterlyReport.pdf'), findsOneWidget);
      expect(find.textContaining('6 Pages'), findsOneWidget);
      expect(find.text('512.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify Mode Selector Options
      expect(find.text('Custom Ranges'), findsOneWidget);
      expect(find.text('Split Every N Pages'), findsOneWidget);
      expect(find.text('Extract All Pages'), findsOneWidget);

      // Verify initial Custom Ranges textfield and default range
      expect(find.byType(TextField), findsOneWidget);

      // Verify Split Action button is present
      expect(find.widgetWithText(ElevatedButton, 'Split PDF'), findsOneWidget);
    },
  );

  testWidgets('PdfSplitProgressPage toggles modes and validates ranges', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(10);
    final mockFile = SelectedPdfFile(
      name: 'Contract.pdf',
      sizeBytes: 1024 * 200,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfSplitProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Switch to Split Every N Pages mode
    await tester.tap(find.byKey(const Key('mode_fixed_chip')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Split every'), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);

    // Switch to Extract All Pages mode
    await tester.tap(find.byKey(const Key('mode_all_chip')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Extract all 10 pages into individual single-page PDFs',
      ),
      findsOneWidget,
    );

    // Switch back to Custom Ranges mode
    await tester.tap(find.byKey(const Key('mode_ranges_chip')));
    await tester.pumpAndSettle();

    // Enter out-of-bounds range
    final textFieldFinder = find.byType(TextField);
    await tester.enterText(textFieldFinder, '1-15');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('exceeds document page count (10)'),
      findsOneWidget,
    );

    // Enter valid range
    await tester.enterText(textFieldFinder, '1-3, 5');
    await tester.pumpAndSettle();

    expect(find.textContaining('exceeds document page count'), findsNothing);
  });
}
