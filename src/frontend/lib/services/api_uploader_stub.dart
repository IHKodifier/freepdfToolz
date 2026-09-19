import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class UploadFileItem {
  final String fieldName;
  final String filename;
  final Uint8List bytes;

  const UploadFileItem({
    String? fieldName,
    String? field,
    required this.filename,
    required this.bytes,
  }) : fieldName = fieldName ?? field ?? 'file';

  String get field => fieldName;
}

class ToolUploadResponse {
  final int statusCode;
  final Uint8List bodyBytes;
  final String bodyString;
  final Map<String, String> headers;

  const ToolUploadResponse({
    required this.statusCode,
    required this.bodyBytes,
    required this.bodyString,
    required this.headers,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  Uint8List get bytes => bodyBytes;

  String? get filename {
    final disposition = headers['content-disposition'];
    if (disposition != null && disposition.contains('filename=')) {
      final regex = RegExp(r'filename=["' "'" r']?([^"' "'" r';\r\n]+)');
      final match = regex.firstMatch(disposition);
      if (match != null && match.group(1) != null) {
        return match.group(1)!.trim();
      }
    }
    return null;
  }
}

/// Fallback uploader for non-web environments (tests, desktop).
Future<Map<String, dynamic>> uploadWithRealSocketProgress({
  required String url,
  required String filename,
  required Uint8List bytes,
  Map<String, String>? headers,
  String? password,
  Function(int sentBytes, int totalBytes)? onProgress,
  Function()? onAnalyzing,
}) async {
  final request = http.MultipartRequest('POST', Uri.parse(url));
  if (headers != null) {
    request.headers.addAll(headers);
  }
  if (password != null && password.isNotEmpty) {
    request.fields['password'] = password;
  }
  request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

  if (onProgress != null) {
    onProgress(bytes.length, bytes.length);
  }
  if (onAnalyzing != null) {
    onAnalyzing();
  }

  final streamed = await request.send();
  final response = await http.Response.fromStream(streamed);

  try {
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return {'statusCode': response.statusCode, 'data': json};
  } catch (_) {
    return {
      'statusCode': response.statusCode,
      'data': {'detail': response.body}
    };
  }
}

/// Fallback tool uploader for non-web environments (tests, desktop).
Future<ToolUploadResponse> executeToolUploadWithProgress({
  required String url,
  required List<UploadFileItem> files,
  Map<String, String>? fields,
  Map<String, String>? headers,
  Function(int sentBytes, int totalBytes)? onProgress,
  Duration pollInterval = const Duration(milliseconds: 600),
}) async {
  final request = http.MultipartRequest('POST', Uri.parse(url));
  if (headers != null) {
    request.headers.addAll(headers);
  }
  if (fields != null) {
    request.fields.addAll(fields);
  }
  int totalBytes = 0;
  for (final file in files) {
    totalBytes += file.bytes.length;
    request.files.add(
      http.MultipartFile.fromBytes(
        file.fieldName,
        file.bytes,
        filename: file.filename,
      ),
    );
  }

  if (onProgress != null) {
    onProgress(0, totalBytes > 0 ? totalBytes : 1);
  }

  final streamed = await request.send();

  if (onProgress != null) {
    onProgress(totalBytes, totalBytes > 0 ? totalBytes : 1);
  }

  final response = await http.Response.fromStream(streamed);

  return ToolUploadResponse(
    statusCode: response.statusCode,
    bodyBytes: response.bodyBytes,
    bodyString: response.body,
    headers: response.headers,
  );
}
