import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../pages/pdf_merge_page.dart' show SelectedPdfFile;
import 'api_service.dart';

class PdfPageThumbnail {
  final int pageIndex;
  final int pageNumber;
  final double width;
  final double height;
  final Uint8List imageBytes;

  PdfPageThumbnail({
    required this.pageIndex,
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.imageBytes,
  });
}

class PdfThumbnailResult {
  final bool isSuccess;
  final int totalPages;
  final List<PdfPageThumbnail> pages;
  final String? errorMessage;
  final String? sessionFileId;
  final bool hasMore;

  PdfThumbnailResult({
    required this.isSuccess,
    required this.totalPages,
    required this.pages,
    this.errorMessage,
    this.sessionFileId,
    this.hasMore = false,
  });

  PdfPageThumbnail? getPage(int pageNumber) {
    for (final p in pages) {
      if (p.pageNumber == pageNumber) return p;
    }
    return null;
  }

  Uint8List? getPageBytes(int index) {
    for (final p in pages) {
      if (p.pageIndex == index) return p.imageBytes;
    }
    return null;
  }

  double? getPageWidth(int index) {
    for (final p in pages) {
      if (p.pageIndex == index) return p.width;
    }
    return null;
  }

  double? getPageHeight(int index) {
    for (final p in pages) {
      if (p.pageIndex == index) return p.height;
    }
    return null;
  }
}

class PdfThumbnailService {
  static final Map<String, PdfThumbnailResult> _cache = {};

  static String _cacheKey(SelectedPdfFile file) {
    return '${file.name}_${file.sizeBytes}_${file.bytes?.lengthInBytes ?? 0}';
  }

  /// Clears in-memory thumbnail cache
  static void clearCache() {
    _cache.clear();
  }

  static List<PdfPageThumbnail> _parsePages(List<dynamic> rawPages) {
    final List<PdfPageThumbnail> thumbnails = [];
    for (final item in rawPages) {
      final map = item as Map<String, dynamic>;
      final pageIndex = map['page_index'] as int? ?? 0;
      final pageNumber = map['page_number'] as int? ?? 1;
      final width = (map['width'] as num?)?.toDouble() ?? 595.0;
      final height = (map['height'] as num?)?.toDouble() ?? 842.0;
      final imgStr = map['image'] as String? ?? '';

      Uint8List bytes;
      if (imgStr.contains(',')) {
        bytes = base64Decode(imgStr.split(',').last);
      } else if (imgStr.isNotEmpty) {
        bytes = base64Decode(imgStr);
      } else {
        bytes = Uint8List(0);
      }

      if (bytes.isNotEmpty) {
        thumbnails.add(
          PdfPageThumbnail(
            pageIndex: pageIndex,
            pageNumber: pageNumber,
            width: width,
            height: height,
            imageBytes: bytes,
          ),
        );
      }
    }
    return thumbnails;
  }

  /// Fetches visual page thumbnails for the given PDF file.
  /// Renders initial viewport batch (16 pages) in < 1-2s and stages file on backend.
  /// Subsequent pages are asynchronously hydrated in the background via onBatchLoaded.
  static Future<PdfThumbnailResult> fetchThumbnails(
    SelectedPdfFile file, {
    int maxPages = 100,
    int dpi = 72,
    int batchSize = 16,
    int maxDimension = 200,
    String? password,
    Function(int sentBytes, int totalBytes)? onProgress,
    Function(List<PdfPageThumbnail> allPages, int totalPages)? onBatchLoaded,
  }) async {
    if (file.bytes == null || file.bytes!.isEmpty) {
      return PdfThumbnailResult(
        isSuccess: false,
        totalPages: 0,
        pages: [],
        errorMessage: 'File has no content bytes.',
      );
    }

    final key = _cacheKey(file);
    if (_cache.containsKey(key)) {
      final cached = _cache[key]!;
      // If cached has all pages or file already fully processed, return
      if (!cached.hasMore || cached.pages.length >= cached.totalPages) {
        return cached;
      }
    }

    try {
      final fields = <String, String>{
        'page_offset': '0',
        'batch_size': batchSize.toString(),
        'max_dimension': maxDimension.toString(),
      };
      if (password != null && password.isNotEmpty) {
        fields['password'] = password;
      }

      final response = await ApiService.uploadToolFiles(
        endpoint: '/tools/render-thumbnails',
        fields: fields,
        files: [
          UploadFileItem(
            field: 'file',
            filename: file.name,
            bytes: file.bytes!,
          ),
        ],
        onProgress: onProgress,
      );

      if (response.isSuccess) {
        final data = jsonDecode(response.bodyString) as Map<String, dynamic>;
        final totalPages = data['total_pages'] as int? ?? 1;
        final sessionFileId = data['session_file_id'] as String?;
        final hasMore = data['has_more'] as bool? ?? false;
        final rawPages = data['pages'] as List<dynamic>? ?? [];

        final initialThumbnails = _parsePages(rawPages);

        final result = PdfThumbnailResult(
          isSuccess: true,
          totalPages: totalPages,
          pages: initialThumbnails,
          sessionFileId: sessionFileId,
          hasMore: hasMore,
        );

        _cache[key] = result;

        // If there are more pages and we have a sessionFileId, asynchronously hydrate the rest
        if (hasMore && sessionFileId != null && sessionFileId.isNotEmpty) {
          _hydrateRemainingThumbnails(
            sessionFileId: sessionFileId,
            startOffset: initialThumbnails.length,
            totalPages: totalPages,
            batchSize: 24, // larger batch size for background hydration
            maxDimension: maxDimension,
            password: password,
            result: result,
            onBatchLoaded: onBatchLoaded,
          );
        }

        return result;
      } else {
        String detail = 'Server responded with status ${response.statusCode}';
        try {
          final errJson = jsonDecode(response.bodyString) as Map<String, dynamic>;
          if (errJson.containsKey('detail')) {
            detail = errJson['detail'].toString();
          }
        } catch (_) {}

        return PdfThumbnailResult(
          isSuccess: false,
          totalPages: 1,
          pages: [],
          errorMessage: detail,
        );
      }
    } catch (e) {
      debugPrint('PdfThumbnailService error: $e');
      return PdfThumbnailResult(
        isSuccess: false,
        totalPages: 1,
        pages: [],
        errorMessage: e.toString(),
      );
    }
  }

  /// Background continuation runner: uses session_file_id with 0 upload bytes.
  static void _hydrateRemainingThumbnails({
    required String sessionFileId,
    required int startOffset,
    required int totalPages,
    required int batchSize,
    required int maxDimension,
    String? password,
    required PdfThumbnailResult result,
    Function(List<PdfPageThumbnail> allPages, int totalPages)? onBatchLoaded,
  }) async {
    int currentOffset = startOffset;

    while (currentOffset < totalPages) {
      try {
        final fields = <String, String>{
          'session_file_id': sessionFileId,
          'page_offset': currentOffset.toString(),
          'batch_size': batchSize.toString(),
          'max_dimension': maxDimension.toString(),
        };
        if (password != null && password.isNotEmpty) {
          fields['password'] = password;
        }

        final response = await ApiService.uploadToolFiles(
          endpoint: '/tools/render-thumbnails',
          fields: fields,
          files: const [], // Zero byte file upload!
        );

        if (!response.isSuccess) {
          debugPrint('Background thumbnail hydration failed: HTTP ${response.statusCode}');
          break;
        }

        final data = jsonDecode(response.bodyString) as Map<String, dynamic>;
        final rawPages = data['pages'] as List<dynamic>? ?? [];
        if (rawPages.isEmpty) break;

        final newThumbnails = _parsePages(rawPages);
        result.pages.addAll(newThumbnails);

        currentOffset += newThumbnails.length;
        onBatchLoaded?.call(result.pages, totalPages);

        final hasMore = data['has_more'] as bool? ?? false;
        if (!hasMore) break;
      } catch (e) {
        debugPrint('Error during background thumbnail hydration: $e');
        break;
      }
    }
  }
}
