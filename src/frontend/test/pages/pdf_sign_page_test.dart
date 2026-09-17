import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_sign_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_sign_progress_page.dart';
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
    'PdfSignPage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfSignPage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Sign PDF'), findsOneWidget);
      expect(
        find.textContaining(
          'Draw, type, or upload verifiable digital signatures to sign PDF documents',
        ),
        findsOneWidget,
      );

      // Verify Dropzone prompt & dynamic limits notice
      expect(find.textContaining('Drop PDF file here to sign'), findsOneWidget);
      expect(find.text('Select PDF File'), findsOneWidget);
      expect(find.text(AppLimitsConfig.dropzoneNoticeText), findsOneWidget);

      // Verify AdSense Banner #1 on landing page
      expect(find.byType(AdSenseBanner), findsOneWidget);
    },
  );

  testWidgets(
    'PdfSignProgressPage renders overview, page selector, and signature controls',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'EmploymentContract.pdf',
        sizeBytes: 1024 * 420,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfSignProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('EmploymentContract.pdf'), findsOneWidget);
      expect(find.textContaining('3 Pages'), findsOneWidget);
      expect(find.textContaining('420.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify Page Selector
      expect(find.textContaining('Page 1 of 3'), findsOneWidget);
      expect(find.byKey(const Key('sign_prev_page_btn')), findsOneWidget);
      expect(find.byKey(const Key('sign_next_page_btn')), findsOneWidget);

      // Verify Signature creation button and placement preview
      expect(
        find.byKey(const Key('open_signature_dialog_btn')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sign_placement_canvas')), findsOneWidget);

      // Verify Apply Signature button
      expect(
        find.widgetWithText(ElevatedButton, 'Apply Signature'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Signature modal opens and switches between Draw, Type, and Upload tabs',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(2);
      final mockFile = SelectedPdfFile(
        name: 'Doc.pdf',
        sizeBytes: 1024 * 100,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfSignProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Tap "Create / Change Signature" button
      await tester.tap(find.text('Create / Change Signature'));
      await tester.pumpAndSettle();

      // Verify modal title and tabs
      expect(find.text('Create Signature'), findsOneWidget);
      expect(find.text('Draw'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);

      // Default tab is Draw: verify Clear Canvas button exists
      expect(find.text('Clear Canvas'), findsOneWidget);

      // Switch to Type tab
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('typed_signature_field')), findsOneWidget);

      // Switch to Upload tab
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      expect(find.text('Select Signature Image (PNG / JPG)'), findsOneWidget);
    },
  );

  testWidgets('Page selector increments and decrements target signing page', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(3);
    final mockFile = SelectedPdfFile(
      name: 'MultiPageDoc.pdf',
      sizeBytes: 1024 * 120,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfSignProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Initially on page 1 of 3
    expect(find.textContaining('Sign on Page 1 of 3'), findsOneWidget);

    // Click Next Page button
    final nextBtn = find.byKey(const Key('sign_next_page_btn'));
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    // Now on page 2 of 3
    expect(find.textContaining('Sign on Page 2 of 3'), findsOneWidget);

    // Click Prev Page button
    final prevBtn = find.byKey(const Key('sign_prev_page_btn'));
    await tester.tap(prevBtn);
    await tester.pumpAndSettle();

    // Back to page 1 of 3
    expect(find.textContaining('Sign on Page 1 of 3'), findsOneWidget);
  });
}
