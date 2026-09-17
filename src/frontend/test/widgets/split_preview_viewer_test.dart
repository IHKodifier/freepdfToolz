import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/widgets/split_preview_viewer.dart';

void main() {
  final samplePages = [
    {
      'page_number': 1,
      'text':
          'Sample Header Page 1\nThis is paragraph one of the OCR document.',
      'lines': [
        {
          'bbox': [10.0, 20.0, 100.0, 30.0],
          'text': 'Sample Header Page 1',
        },
        {
          'bbox': [10.0, 40.0, 200.0, 50.0],
          'text': 'This is paragraph one of the OCR document.',
        },
      ],
    },
    {
      'page_number': 2,
      'text': 'Page 2 Content\nConclusion section text.',
      'lines': [
        {
          'bbox': [10.0, 20.0, 100.0, 30.0],
          'text': 'Page 2 Content',
        },
      ],
    },
  ];

  testWidgets('SplitPreviewViewer renders split panes and header controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitPreviewViewer(
            jobId: 'test_job_1',
            filename: 'sample_doc.pdf',
            pages: samplePages,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify filename header & page indicator
    expect(find.text('sample_doc.pdf'), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);

    // Verify format tabs
    expect(find.text('Plain Text (.txt)'), findsOneWidget);
    expect(find.text('Markdown (.md)'), findsOneWidget);

    // Verify initial text content on Page 1
    expect(find.textContaining('Sample Header Page 1'), findsWidgets);
  });

  testWidgets('SplitPreviewViewer navigates pages correctly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitPreviewViewer(
            jobId: 'test_job_1',
            filename: 'sample_doc.pdf',
            pages: samplePages,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Next Page button
    final nextBtn = find.byIcon(Icons.chevron_right);
    expect(nextBtn, findsOneWidget);
    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    // Verify Page 2 content displayed
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.textContaining('Page 2 Content'), findsWidgets);
  });

  testWidgets('SplitPreviewViewer switches format tabs between txt and md', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitPreviewViewer(
            jobId: 'test_job_1',
            filename: 'sample_doc.pdf',
            pages: samplePages,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Switch to Markdown tab
    final mdTab = find.text('Markdown (.md)');
    await tester.tap(mdTab);
    await tester.pumpAndSettle();

    // Markdown view active
    expect(find.textContaining('Sample Header Page 1'), findsWidgets);
  });

  testWidgets('SplitPreviewViewer renders download button and options', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitPreviewViewer(
            jobId: 'test_job_1',
            filename: 'sample_doc.pdf',
            pages: samplePages,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Download button exists in top header
    final downloadBtn = find.text('Download');
    expect(downloadBtn, findsOneWidget);

    // Tap download button to show popup options
    await tester.tap(downloadBtn);
    await tester.pumpAndSettle();

    // Verify download menu options render
    expect(find.text('Searchable PDF (.pdf)'), findsOneWidget);
    expect(find.text('Plain Text (.txt)'), findsWidgets);
    expect(find.text('Markdown (.md)'), findsWidgets);
    expect(find.text('Send Email Links (24h)'), findsOneWidget);
  });

  testWidgets(
    'SplitPreviewViewer opens Email Delivery Dialog with explicit privacy warning banner',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SplitPreviewViewer(
              jobId: 'test_job_1',
              filename: 'sample_doc.pdf',
              pages: samplePages,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Email Links icon button in header
      final emailBtn = find.byIcon(Icons.email_outlined);
      expect(emailBtn, findsOneWidget);
      await tester.tap(emailBtn);
      await tester.pumpAndSettle();

      // Verify dialog title, privacy warning banner, and send button render
      expect(find.text('Email Download Links'), findsOneWidget);
      expect(
        find.text(
          'Input file is deleted immediately. Ensure email address is correct.',
        ),
        findsOneWidget,
      );
      expect(find.text('Send Download Links'), findsOneWidget);
    },
  );

  testWidgets(
    'SplitPreviewViewer renders document preview with zoom slider & pan/zoom controls',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SplitPreviewViewer(
              jobId: 'test_job_zoom',
              filename: 'zoom_test.pdf',
              pages: samplePages,
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify Document Page Preview label
      expect(find.text('Document Page Preview'), findsOneWidget);

      // Verify Zoom Controls: Zoom In, Zoom Out, 100% chip, Slider
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);

      // Tap Zoom In and verify zoom percentage increases
      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pump();
      expect(find.text('125%'), findsOneWidget);

      // Tap Zoom Out and verify zoom percentage decreases
      await tester.tap(find.byIcon(Icons.zoom_out));
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);

      // Tap Reset chip after zooming
      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pump();
      expect(find.text('125%'), findsOneWidget);
      await tester.tap(find.text('125%'));
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);
    },
  );

  testWidgets(
    'SplitPreviewViewer on mobile hides preview pane and shows wrapped download actions',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SplitPreviewViewer(
              jobId: 'test_job_mobile',
              filename: 'receipt_2026.pdf',
              pages: samplePages,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Preview pane and zoom controls must NOT be present on mobile
      expect(find.text('Document Page Preview'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byIcon(Icons.zoom_in), findsNothing);
      expect(find.byIcon(Icons.zoom_out), findsNothing);

      // 2. Wrapped download actions must be present and visible
      expect(find.text('Download Searchable PDF'), findsOneWidget);
      expect(find.text('Download .TXT'), findsOneWidget);
      expect(find.text('Download .MD'), findsOneWidget);
      expect(find.byIcon(Icons.email_outlined), findsWidgets);

      // 3. Extracted text and controls must be present
      expect(find.text('Plain Text (.txt)'), findsOneWidget);
      expect(find.text('Markdown (.md)'), findsOneWidget);
      expect(find.text('Copy Text'), findsOneWidget);
      expect(find.textContaining('Sample Header Page 1'), findsWidgets);
    },
  );
}
