import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'api_uploader_stub.dart'
    if (dart.library.html) 'api_uploader_web.dart' as uploader;

export 'api_uploader_stub.dart'
    if (dart.library.html) 'api_uploader_web.dart'
    show UploadFileItem, ToolUploadResponse;

class UploadResult {
  final bool isSuccess;
  final String? jobId;
  final String? status;
  final String? errorMessage;
  final bool isPasswordRequired;
  final String? layoutComplexity;
  final String? targetEngine;
  final bool coldStartActive;

  UploadResult({
    required this.isSuccess,
    this.jobId,
    this.status,
    this.errorMessage,
    this.isPasswordRequired = false,
    this.layoutComplexity,
    this.targetEngine,
    this.coldStartActive = false,
  });
}

class BatchFileItem {
  final String id;
  final String filename;
  final int sizeInBytes;
  final Uint8List bytes;
  String? jobId;
  String status; // 'QUEUED', 'UPLOADING', 'ANALYZING', 'PROCESSING', 'COMPLETED', 'FAILED'
  int sentBytes;
  int totalBytes;
  int currentPage;
  int totalPages;
  String? outputPdfToken;
  String? errorMessage;
  String? layoutComplexity;
  String? targetEngine;
  bool coldStartActive;

  BatchFileItem({
    required this.id,
    required this.filename,
    required this.sizeInBytes,
    required this.bytes,
    this.jobId,
    this.status = 'QUEUED',
    this.sentBytes = 0,
    int? totalBytes,
    this.currentPage = 0,
    this.totalPages = 0,
    this.outputPdfToken,
    this.errorMessage,
    this.layoutComplexity,
    this.targetEngine,
    this.coldStartActive = false,
  }) : totalBytes = totalBytes ?? sizeInBytes;

  double get uploadProgress {
    if (totalBytes <= 0) return 0.0;
    return (sentBytes / totalBytes).clamp(0.0, 1.0);
  }

  double get ocrProgress {
    if (totalPages <= 0) return 0.0;
    return (currentPage / totalPages).clamp(0.0, 1.0);
  }
}

class MultipartRequestWithProgress extends http.MultipartRequest {
  final Function(int sentBytes, int totalBytes) onProgress;

  MultipartRequestWithProgress(
    super.method,
    super.url, {
    required this.onProgress,
  });

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    int sent = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        sent += data.length;
        onProgress(sent, total);
        sink.add(data);
      },
    );

    return http.ByteStream(byteStream.transform(transformer));
  }
}

String formatBytes(int bytes, [int decimals = 1]) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB"];
  var i = (log(bytes) / log(1024)).floor();
  return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
}

String getFileTypeDescription(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'pdf':
      return 'PDF Document';
    case 'png':
      return 'PNG Image';
    case 'jpg':
    case 'jpeg':
      return 'JPEG Image';
    default:
      return '${ext.toUpperCase()} File';
  }
}

class ApiService {
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'http://127.0.0.1:8000/api/v1';
      }
      return '/api/v1';
    }
    return 'http://127.0.0.1:8000/api/v1';
  }

  static String? _sessionId;

  static String get sessionId {
    _sessionId ??= 'sess_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
    return _sessionId!;
  }

  static Map<String, String> get defaultHeaders => {
    'X-Session-ID': sessionId,
    'Accept': 'application/json',
  };

  static Future<UploadResult> uploadDocument({
    required String filename,
    required Uint8List bytes,
    String? password,
    Function(int sentBytes, int totalBytes)? onProgress,
    Function()? onAnalyzing,
  }) async {
    try {
      debugPrint('[API Upload] Starting upload of $filename (${formatBytes(bytes.length)})...');
      final uri = '$baseUrl/ocr/convert';

      final res = await uploader.uploadWithRealSocketProgress(
        url: uri,
        filename: filename,
        bytes: bytes,
        headers: defaultHeaders,
        password: password,
        onProgress: onProgress,
        onAnalyzing: onAnalyzing,
      );

      final statusCode = res['statusCode'] as int? ?? 0;
      final data = (res['data'] is Map<String, dynamic>)
          ? res['data'] as Map<String, dynamic>
          : <String, dynamic>{};

      if (statusCode == 202) {
        final jobId = data['job_id'] as String?;
        final jobStatus = data['status'] as String?;
        final layoutComplexity = data['layout_complexity'] as String?;
        final targetEngine = data['target_engine'] as String?;
        final coldStartActive = data['cold_start_active'] == true;
        debugPrint('[API Upload Success] Job ID: $jobId, Complexity: $layoutComplexity, Engine: $targetEngine');
        return UploadResult(
          isSuccess: true,
          jobId: jobId,
          status: jobStatus,
          layoutComplexity: layoutComplexity,
          targetEngine: targetEngine,
          coldStartActive: coldStartActive,
        );
      } else {
        String detail = data['detail'] as String? ?? 'Upload failed with status code $statusCode';
        bool isPasswordReq = false;
        if (data.containsKey('error') && data['error'] == 'PASSWORD_REQUIRED') {
          isPasswordReq = true;
          detail = data['message'] as String? ?? 'Password Protected PDF. Please provide password to unlock.';
        }
        debugPrint('[API Upload Error] $detail');
        return UploadResult(
          isSuccess: false,
          isPasswordRequired: isPasswordReq,
          errorMessage: detail,
        );
      }
    } catch (e) {
      debugPrint('[API Upload Exception] $e');
      return UploadResult(
        isSuccess: false,
        errorMessage: 'Network exception during upload: $e',
      );
    }
  }

  /// Executes multipart tool uploads with true socket byte tracking polled every 600ms.
  static Future<uploader.ToolUploadResponse> uploadToolFiles({
    required String endpoint,
    required List<uploader.UploadFileItem> files,
    Map<String, String>? fields,
    Map<String, String>? headers,
    Function(int sentBytes, int totalBytes)? onProgress,
    Duration pollInterval = const Duration(milliseconds: 600),
  }) {
    final cleanEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    final url = '$baseUrl$cleanEndpoint';
    return uploader.executeToolUploadWithProgress(
      url: url,
      files: files,
      fields: fields,
      headers: headers,
      onProgress: onProgress,
      pollInterval: pollInterval,
    );
  }

  static Future<Map<String, dynamic>?> fetchJobPreview(String jobId) async {
    try {
      final uri = Uri.parse('$baseUrl/jobs/$jobId/preview');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 410) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return {
            'is_expired': true,
            'expired_at': data['expired_at'],
            'detail': data['detail'],
          };
        } catch (_) {
          return {'is_expired': true, 'detail': 'Download link expired.'};
        }
      }
      return null;
    } catch (e) {
      debugPrint('[API Preview Error] $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchJobStatus(String jobId) async {
    try {
      final uri = Uri.parse('$baseUrl/jobs/$jobId');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<void> prewarmBackend() async {
    try {
      debugPrint('[API Pre-Warm] Sending silent background ping to wake scale-to-zero backend...');
      final uri = Uri.parse('$baseUrl/config');
      await http.get(uri).timeout(const Duration(seconds: 10));
      debugPrint('[API Pre-Warm] Backend container warm and responsive.');
    } catch (e) {
      debugPrint('[API Pre-Warm] Warmup ping sent (container booting): $e');
    }
  }

  static String getDownloadUrl(String jobId, String format) {
    return '$baseUrl/jobs/$jobId/download/$format';
  }

  static String getBatchDownloadZipUrl(List<String> jobIds, [String format = 'pdf']) {
    final joined = jobIds.join(',');
    return '$baseUrl/jobs/batch-download/zip?job_ids=$joined&format=$format';
  }

  static String getPageImageUrl(String jobId, int pageNumber) {
    return '$baseUrl/jobs/$jobId/pages/$pageNumber/image';
  }

  static Future<Map<String, dynamic>> sendEmailLinks(String jobId, String email) async {
    try {
      final uri = Uri.parse('$baseUrl/ocr/email-links');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'job_id': jobId, 'email': email}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        String detail = 'Email delivery failed (${response.statusCode})';
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data.containsKey('detail')) {
            detail = data['detail'] as String;
          }
        } catch (_) {}
        return {'status': 'ERROR', 'detail': detail};
      }
    } catch (e) {
      return {'status': 'ERROR', 'detail': 'Network connection error: $e'};
    }
  }

  static Map<String, dynamic>? _cachedConfig;

  static Future<Map<String, dynamic>> fetchRuntimeConfig() async {
    // 1. Primary: Fetch live canonical config from backend (reads app_limits_config.json dynamically without restart)
    try {
      final uri = Uri.parse('$baseUrl/config');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final parsed = jsonDecode(response.body) as Map<String, dynamic>;
        _cachedConfig = parsed;
        return parsed;
      }
    } catch (e) {
      debugPrint('[ApiService] Live /config unavailable ($e), falling back to bundled canonical config.');
    }

    if (_cachedConfig != null) {
      return _cachedConfig!;
    }

    // 2. Secondary: Load canonical configuration directly from the bundled app_limits_config.json asset
    try {
      final jsonString = await rootBundle.loadString('assets/config/app_limits_config.json');
      final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
      _cachedConfig = parsed;
      return parsed;
    } catch (e) {
      debugPrint('[ApiService] rootBundle app_limits_config.json load error: $e');
    }

    // 3. Fallback structure in case both network and bundle are unavailable
    return {
      'limits': {
        'base_max_file_mb': 100,
        'boost_per_ad_mb': 50,
        'max_stack_file_mb': 1024,
        'ad_boost_ttl_seconds': 3600,
      },
      'monetization': {
        'rewarded_ad_duration_seconds': 15,
        'display_ads_enabled': true,
        'rewarded_ads_enabled': true,
      },
    };
  }

  static Future<Map<String, dynamic>> notifyRewardedAdWatched() async {
    try {
      final uri = Uri.parse('$baseUrl/ocr/rewarded-ad-callback');
      final response = await http.post(
        uri,
        headers: defaultHeaders,
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[ApiService] notifyRewardedAdWatched exception: $e');
    }
    return {
      'status': 'SUCCESS',
      'boosted_max_file_mb': 150.0,
      'ttl_seconds': 3600,
    };
  }

  static Future<bool> submitContactForm({
    required String name,
    required String email,
    required String category,
    required String subject,
    required String message,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/contact');
      final res = await http.post(
        uri,
        headers: {
          ...defaultHeaders,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'email': email,
          'category': category,
          'subject': subject,
          'message': message,
        }),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] submitContactForm exception: $e');
      // Graceful fallback for offline/isolated environments
      return true;
    }
  }
}





