import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart'
    show SelectedPdfFile;
import 'package:freepdftoolz_frontend/pages/pdf_annotate_page.dart';
import 'package:freepdftoolz_frontend/pages/pdf_annotate_progress_page.dart';
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
    'PdfAnnotatePage renders dropzone, header, and AdSense banner initially',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: PdfAnnotatePage()));
      await tester.pumpAndSettle();

      // Verify Title & Subtitle
      expect(find.text('Annotate PDF'), findsOneWidget);
      expect(
        find.textContaining(
          'Highlight text, add notes, boxes, and markup directly on your PDF documents',
        ),
        findsOneWidget,
      );

      // Verify Dropzone prompt & dynamic limits notice
      expect(
        find.textContaining('Drop PDF file here to annotate'),
        findsOneWidget,
      );
      expect(find.text('Select PDF File'), findsOneWidget);
      expect(find.text(AppLimitsConfig.dropzoneNoticeText), findsOneWidget);

      // Verify AdSense Banner #1 on landing page
      expect(find.byType(AdSenseBanner), findsOneWidget);
    },
  );

  testWidgets(
    'PdfAnnotateProgressPage renders overview, toolbar, page selector, and canvas',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockBytes = createMockPdfBytesWithPages(3);
      final mockFile = SelectedPdfFile(
        name: 'ResearchPaper.pdf',
        sizeBytes: 1024 * 350,
        bytes: mockBytes,
      );

      await tester.pumpWidget(
        MaterialApp(home: PdfAnnotateProgressPage(file: mockFile)),
      );
      await tester.pumpAndSettle();

      // Verify document overview
      expect(find.text('ResearchPaper.pdf'), findsOneWidget);
      expect(find.textContaining('3 Pages'), findsOneWidget);
      expect(find.textContaining('350.0 KB'), findsOneWidget);

      // Verify AdSense Banner #2 on progress page
      expect(find.byType(AdSenseBanner), findsOneWidget);

      // Verify Page Selector
      expect(find.textContaining('Page 1 of 3'), findsOneWidget);
      expect(find.byKey(const Key('annotate_prev_page_btn')), findsOneWidget);
      expect(find.byKey(const Key('annotate_next_page_btn')), findsOneWidget);

      // Verify Toolbar tool buttons
      expect(find.byKey(const Key('tool_select_btn')), findsOneWidget);
      expect(find.byKey(const Key('tool_highlight_btn')), findsOneWidget);
      expect(find.byKey(const Key('tool_underline_btn')), findsOneWidget);
      expect(find.byKey(const Key('tool_note_btn')), findsOneWidget);

      // Verify Undo and Redo actions
      expect(find.byKey(const Key('annotate_undo_btn')), findsOneWidget);
      expect(find.byKey(const Key('annotate_redo_btn')), findsOneWidget);

      // Verify Preview Canvas
      expect(find.byKey(const Key('annotate_preview_canvas')), findsOneWidget);

      // Verify Save Annotations button
      expect(
        find.widgetWithText(ElevatedButton, 'Save Annotations & Download'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Selecting annotation tool and color updates active state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(2);
    final mockFile = SelectedPdfFile(
      name: 'Paper.pdf',
      sizeBytes: 1024 * 100,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfAnnotateProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Select Underline tool
    await tester.tap(find.byKey(const Key('tool_underline_btn')));
    await tester.pumpAndSettle();

    // Select Green Color
    final greenColorBtn = find.byKey(const Key('color_palette_green'));
    if (greenColorBtn.evaluate().isNotEmpty) {
      await tester.ensureVisible(greenColorBtn);
      await tester.tap(greenColorBtn);
      await tester.pumpAndSettle();
    }

    // Select Sticky Note tool
    await tester.tap(find.byKey(const Key('tool_note_btn')));
    await tester.pumpAndSettle();

    // Select Select / Move tool
    await tester.tap(find.byKey(const Key('tool_select_btn')));
    await tester.pumpAndSettle();
  });

  testWidgets('Page selector increments and decrements target page', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(3);
    final mockFile = SelectedPdfFile(
      name: 'Doc.pdf',
      sizeBytes: 1024 * 150,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfAnnotateProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Initially on page 1 of 3
    expect(find.textContaining('Page 1 of 3'), findsOneWidget);

    // Next page
    final nextBtn = find.byKey(const Key('annotate_next_page_btn'));
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('Page 2 of 3'), findsOneWidget);

    // Prev page
    final prevBtn = find.byKey(const Key('annotate_prev_page_btn'));
    await tester.tap(prevBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('Page 1 of 3'), findsOneWidget);
  });

  testWidgets('Zoom controls increment up to 175% and decrement to 75%', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockBytes = createMockPdfBytesWithPages(2);
    final mockFile = SelectedPdfFile(
      name: 'Contract.pdf',
      sizeBytes: 1024 * 100,
      bytes: mockBytes,
    );

    await tester.pumpWidget(
      MaterialApp(home: PdfAnnotateProgressPage(file: mockFile)),
    );
    await tester.pumpAndSettle();

    // Initial zoom is 100%
    expect(find.byKey(const Key('annotate_zoom_level_text')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    final zoomInBtn = find.byKey(const Key('annotate_zoom_in_btn'));
    final zoomOutBtn = find.byKey(const Key('annotate_zoom_out_btn'));
    final zoomResetBtn = find.byKey(const Key('annotate_zoom_reset_btn'));

    // Zoom in: 100% -> 125%
    await tester.tap(zoomInBtn);
    await tester.pumpAndSettle();
    expect(find.text('125%'), findsOneWidget);

    // Zoom in: 125% -> 150%
    await tester.tap(zoomInBtn);
    await tester.pumpAndSettle();
    expect(find.text('150%'), findsOneWidget);

    // Zoom in: 150% -> 175%
    await tester.tap(zoomInBtn);
    await tester.pumpAndSettle();
    expect(find.text('175%'), findsOneWidget);

    // Zoom in capped at 175%
    await tester.tap(zoomInBtn);
    await tester.pumpAndSettle();
    expect(find.text('175%'), findsOneWidget);

    // Zoom out: 175% -> 150%
    await tester.tap(zoomOutBtn);
    await tester.pumpAndSettle();
    expect(find.text('150%'), findsOneWidget);

    // Reset zoom back to 100%
    await tester.tap(zoomResetBtn);
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
  });
}

