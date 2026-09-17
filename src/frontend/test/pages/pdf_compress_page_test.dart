import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_compress_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_compress_progress_page.dart';
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
    'PdfCompressPage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfCompressPage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Compress PDF'), findsOneWidget);
      expect(
        find.textContaining(
          'Reduce PDF file size while preserving high visual resolution',
        ),
        findsOneWidget,
      );

      // Verify Dropzone prompt & dynamic limits notice
      expect(
        find.textContaining('Drop PDF file here to compress'),
        findsOneWidget,
      );
      expect(find.text('Select PDF File'), findsOneWidget);
      expect(find.text(AppLimitsConfig.dropzoneNoticeText), findsOneWidget);

      // Verify AdSense Banner #1 on landing page
      expect(find.byType(AdSenseBanner), findsOneWidget);
    },
  );

  testWidgets(
    'PdfCompressProgressPage renders overview, 3 preset cards, and AdSense banner',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(4);
      final mockFile = SelectedPdfFile(
        name: 'FinancialStatement.pdf',
        sizeBytes: 1024 * 512,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfCompressProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('FinancialStatement.pdf'), findsOneWidget);
      expect(find.textContaining('4 Pages'), findsOneWidget);
      expect(find.textContaining('512.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify 3 Presets
      expect(find.byKey(const Key('preset_recommended')), findsOneWidget);
      expect(find.byKey(const Key('preset_extreme')), findsOneWidget);
      expect(find.byKey(const Key('preset_low')), findsOneWidget);

      expect(find.text('Recommended Compression'), findsOneWidget);
      expect(find.text('Extreme Compression'), findsOneWidget);
      expect(find.text('Low / Lossless Compression'), findsOneWidget);

      // Verify Action button
      expect(
        find.widgetWithText(ElevatedButton, 'Compress PDF'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Tapping compression level presets updates selection state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(2);
    final mockFile = SelectedPdfFile(
      name: 'SampleDoc.pdf',
      sizeBytes: 1024 * 200,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfCompressProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Tap Extreme preset
    await tester.tap(find.byKey(const Key('preset_extreme')));
    await tester.pumpAndSettle();

    final extremeRadio = tester.widget<Radio<String>>(
      find.descendant(
        of: find.byKey(const Key('preset_extreme')),
        matching: find.byType(Radio<String>),
      ),
    );
    expect(extremeRadio.groupValue, equals('extreme'));

    // Tap Low Lossless preset
    await tester.tap(find.byKey(const Key('preset_low')));
    await tester.pumpAndSettle();

    final lowRadio = tester.widget<Radio<String>>(
      find.descendant(
        of: find.byKey(const Key('preset_low')),
        matching: find.byType(Radio<String>),
      ),
    );
    expect(lowRadio.groupValue, equals('low'));
  });
}
