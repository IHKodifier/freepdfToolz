import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/services/api_service.dart';
import 'package:freepdftoolz_frontend/widgets/ocr_progress_view.dart';

void main() {
  testWidgets(
    'OcrProgressView renders progress indicator, page count, and status',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OcrProgressView(
              currentPage: 3,
              totalPages: 8,
              status: 'PROCESSING',
            ),
          ),
        ),
      );

      // Verify status and page text
      expect(find.text('Processing Document...'), findsOneWidget);
      expect(find.textContaining('Page 3 of 8'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    },
  );

  testWidgets('OcrProgressView renders completed status when finished', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OcrProgressView(
            currentPage: 8,
            totalPages: 8,
            status: 'COMPLETED',
          ),
        ),
      ),
    );

    expect(find.text('Conversion Complete!'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets(
    'OcrProgressView renders batch completion actions with View and Download buttons',
    (WidgetTester tester) async {
      final batchItems = [
        BatchFileItem(
          id: 'file_1',
          filename: 'doc1.pdf',
          sizeInBytes: 1024,
          bytes: Uint8List(0),
          jobId: 'job_1',
          status: 'COMPLETED',
          currentPage: 2,
          totalPages: 2,
        ),
        BatchFileItem(
          id: 'file_2',
          filename: 'doc2.png',
          sizeInBytes: 2048,
          bytes: Uint8List(0),
          jobId: 'job_2',
          status: 'COMPLETED',
          currentPage: 1,
          totalPages: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OcrProgressView(batchItems: batchItems)),
        ),
      );

      expect(find.text('Batch Processing Complete!'), findsOneWidget);
      expect(find.text('2 of 2 Files Converted'), findsOneWidget);
      expect(find.text('doc1.pdf'), findsOneWidget);
      expect(find.text('doc2.png'), findsOneWidget);
      expect(find.text('View'), findsNWidgets(2));
      expect(find.text('PDF'), findsNWidgets(2));
      expect(
        find.textContaining('Download All as ZIP (2 Searchable PDFs)'),
        findsOneWidget,
      );
    },
  );
}
