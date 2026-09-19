import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  PdfThumbnailResult({
    required this.isSuccess,
    required this.totalPages,
    required this.pages,
    this.errorMessage,
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

  /// Fetches real page thumbnails for the given PDF file with real socket upload tracking
  static Future<PdfThumbnailResult> fetchThumbnails(
    SelectedPdfFile file, {
    int maxPages = 100,
    int dpi = 72,
    String? password,
    Function(int sentBytes, int totalBytes)? onProgress,
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
      return _cache[key]!;
    }

    try {
      final fields = <String, String>{
        'max_pages': maxPages.toString(),
        'dpi': dpi.toString(),
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
        final rawPages = data['pages'] as List<dynamic>? ?? [];

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

        final result = PdfThumbnailResult(
          isSuccess: true,
          totalPages: totalPages,
          pages: thumbnails,
        );

        _cache[key] = result;
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
}
