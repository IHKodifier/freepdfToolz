import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_redact_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_redact_progress_page.dart';
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
    'PdfRedactPage renders header, dropzone, security card, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfRedactPage()));
      await tester.pumpAndSettle();

      // Verify Title & Description
      expect(find.text('Redact PDF'), findsOneWidget);
      expect(
        find.textContaining(
          'Permanently black out sensitive text, data, and confidential areas',
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
    'PdfRedactProgressPage renders overview, search & redact bar, and security guarantee shield',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(2);
      final mockFile = SelectedPdfFile(
        name: 'ConfidentialAgreement.pdf',
        sizeBytes: 1024 * 350,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfRedactProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('ConfidentialAgreement.pdf'), findsOneWidget);
      expect(find.textContaining('2 Pages'), findsOneWidget);
      expect(find.text('350.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify Search & Redact Input and Case Sensitivity Toggle
      expect(find.text('Search & Redact Text'), findsOneWidget);
      expect(find.text('Match exact case'), findsOneWidget);

      // Verify Security Guarantee Banner
      expect(
        find.textContaining('True Cryptographic Sanitization'),
        findsOneWidget,
      );

      // Verify Action button
      expect(find.text('Sanitize & Redact PDF'), findsOneWidget);
    },
  );

  testWidgets(
    'Entering search phrase updates input controller and enables action',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(1);
      final mockFile = SelectedPdfFile(
        name: 'SecretRecord.pdf',
        sizeBytes: 1024 * 120,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfRedactProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Enter search text
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsWidgets);
      await tester.enterText(textFieldFinder.first, 'TOP_SECRET');
      await tester.pumpAndSettle();

      expect(find.text('TOP_SECRET'), findsOneWidget);
    },
  );

  testWidgets('Toggling case sensitivity switch updates state correctly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(1);
    final mockFile = SelectedPdfFile(
      name: 'SecretRecord.pdf',
      sizeBytes: 1024 * 120,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfRedactProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);

    // Toggle switch on
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    final Switch switchWidget = tester.widget(switchFinder);
    expect(switchWidget.value, isTrue);
  });
}
