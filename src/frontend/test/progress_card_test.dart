import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/widgets/progress_card.dart';

void main() {
  testWidgets('ProgressCard renders QUEUED status correctly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProgressCard(
            jobId: 'test-job-1',
            status: 'QUEUED',
            currentPage: 0,
            totalPages: 5,
          ),
        ),
      ),
    );

    expect(find.text('QUEUED'), findsOneWidget);
    expect(
      find.text('Preparing document for OCR processing...'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('ProgressCard renders PROCESSING status with page count', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProgressCard(
            jobId: 'test-job-2',
            status: 'PROCESSING',
            currentPage: 3,
            totalPages: 8,
          ),
        ),
      ),
    );

    expect(find.text('PROCESSING'), findsOneWidget);
    expect(find.text('Page 3 of 8'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('ProgressCard renders COMPLETED status with download token', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProgressCard(
            jobId: 'test-job-3',
            status: 'COMPLETED',
            currentPage: 8,
            totalPages: 8,
            outputPdfToken: 'token-12345',
          ),
        ),
      ),
    );

    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('Conversion Complete!'), findsOneWidget);
    expect(find.text('Download Searchable PDF'), findsOneWidget);
  });

  testWidgets('ProgressCard renders FAILED status with error message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProgressCard(
            jobId: 'test-job-4',
            status: 'FAILED',
            currentPage: 1,
            totalPages: 5,
            errorMessage: 'Document contains corrupted pages.',
          ),
        ),
      ),
    );

    expect(find.text('FAILED'), findsOneWidget);
    expect(find.text('Document contains corrupted pages.'), findsOneWidget);
  });
}
