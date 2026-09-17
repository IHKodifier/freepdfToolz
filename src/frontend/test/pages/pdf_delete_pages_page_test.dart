import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_delete_pages_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_delete_pages_progress_page.dart';
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
    'PdfDeletePagesPage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfDeletePagesPage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Delete PDF Pages'), findsOneWidget);
      expect(
        find.textContaining('Remove unwanted, blank, or duplicate pages'),
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
    'PdfDeletePagesProgressPage renders document overview, page cards, status bar, and delete button',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'ConfidentialDoc.pdf',
        sizeBytes: 1024 * 300,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfDeletePagesProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('ConfidentialDoc.pdf'), findsOneWidget);
      expect(find.textContaining('3 Pages'), findsOneWidget);
      expect(find.text('300.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify Quick Action buttons
      expect(find.text('Select All'), findsOneWidget);
      expect(find.text('Clear Selection'), findsOneWidget);

      // Verify Page cards
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Page 3'), findsOneWidget);

      // Initially 0 pages selected for deletion
      expect(
        find.textContaining('0 of 3 pages marked to remove'),
        findsOneWidget,
      );

      // Verify primary action button
      expect(
        find.widgetWithText(ElevatedButton, 'Delete Pages & Generate PDF'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PdfDeletePagesProgressPage toggling card marks for deletion and updates status',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'Statement.pdf',
        sizeBytes: 1024 * 150,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfDeletePagesProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Tap Page 2 card (index 1) to mark for deletion
      final page2Finder = find.byKey(const Key('page_card_1'));
      expect(page2Finder, findsOneWidget);
      await tester.tap(page2Finder);
      await tester.pumpAndSettle();

      // Verify DELETE overlay tag appears
      expect(find.text('DELETE'), findsOneWidget);

      // Status bar should update to 1 of 3 marked
      expect(
        find.textContaining('1 of 3 pages marked to remove'),
        findsOneWidget,
      );
      expect(find.textContaining('2 pages will remain'), findsOneWidget);

      // Tap again to unmark
      await tester.tap(page2Finder);
      await tester.pumpAndSettle();

      // DELETE overlay disappears
      expect(find.text('DELETE'), findsNothing);
      expect(
        find.textContaining('0 of 3 pages marked to remove'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PdfDeletePagesProgressPage selecting all pages disables delete button with guard warning',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(2);
      final mockFile = SelectedPdfFile(
        name: 'TwoPage.pdf',
        sizeBytes: 1024 * 100,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfDeletePagesProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Tap Select All
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      // Both pages marked DELETE
      expect(find.text('DELETE'), findsNWidgets(2));

      // Warning guard should appear
      expect(
        find.textContaining('A PDF must retain at least one page'),
        findsOneWidget,
      );

      // Action button should be disabled
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Delete Pages & Generate PDF'),
      );
      expect(button.onPressed, isNull);
    },
  );
}
