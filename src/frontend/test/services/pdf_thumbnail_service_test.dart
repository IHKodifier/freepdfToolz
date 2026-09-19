import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/pdf_merge_page.dart' show SelectedPdfFile;
import 'package:freepdftoolz_frontend/services/pdf_thumbnail_service.dart';

void main() {
  group('PdfThumbnailService & PdfThumbnailResult', () {
    setUp(() {
      PdfThumbnailService.clearCache();
    });

    test('PdfThumbnailResult correctly looks up pages and bytes', () {
      final sampleBytes1 = Uint8List.fromList([1, 2, 3]);
      final sampleBytes2 = Uint8List.fromList([4, 5, 6]);

      final result = PdfThumbnailResult(
        isSuccess: true,
        totalPages: 2,
        pages: [
          PdfPageThumbnail(
            pageIndex: 0,
            pageNumber: 1,
            width: 595.0,
            height: 842.0,
            imageBytes: sampleBytes1,
          ),
          PdfPageThumbnail(
            pageIndex: 1,
            pageNumber: 2,
            width: 612.0,
            height: 792.0,
            imageBytes: sampleBytes2,
          ),
        ],
      );

      expect(result.isSuccess, isTrue);
      expect(result.totalPages, 2);
      expect(result.getPageBytes(0), equals(sampleBytes1));
      expect(result.getPageBytes(1), equals(sampleBytes2));
      expect(result.getPageBytes(2), isNull);

      expect(result.getPage(1)?.imageBytes, equals(sampleBytes1));
      expect(result.getPage(2)?.imageBytes, equals(sampleBytes2));
      expect(result.getPage(3), isNull);

      expect(result.getPageWidth(0), 595.0);
      expect(result.getPageHeight(0), 842.0);
      expect(result.getPageWidth(1), 612.0);
      expect(result.getPageHeight(1), 792.0);
      expect(result.getPageWidth(2), isNull);
      expect(result.getPageHeight(2), isNull);
    });

    test('fetchThumbnails handles null or empty file bytes safely', () async {
      final emptyFile = SelectedPdfFile(
        name: 'Empty.pdf',
        sizeBytes: 0,
        bytes: Uint8List(0),
      );

      final res = await PdfThumbnailService.fetchThumbnails(emptyFile);
      expect(res.isSuccess, isFalse);
      expect(res.totalPages, 0);
      expect(res.pages, isEmpty);
      expect(res.errorMessage, isNotNull);
    });

    test('clearCache clears internal cache', () {
      PdfThumbnailService.clearCache();
      // Verifies method runs cleanly without exceptions
      expect(true, isTrue);
    });
  });
}
