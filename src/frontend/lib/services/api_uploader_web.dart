// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

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

/// Native browser XMLHttpRequest uploader that tracks real network socket upload bytes
/// and throttles UI notifications to 600ms for smooth, realistic progress updates.
Future<Map<String, dynamic>> uploadWithRealSocketProgress({
  required String url,
  required String filename,
  required Uint8List bytes,
  Map<String, String>? headers,
  String? password,
  Function(int sentBytes, int totalBytes)? onProgress,
  Function()? onAnalyzing,
}) {
  final completer = Completer<Map<String, dynamic>>();
  final xhr = html.HttpRequest();

  xhr.open('POST', url);

  if (headers != null) {
    headers.forEach((key, value) {
      xhr.setRequestHeader(key, value);
    });
  }

  final formData = html.FormData();
  final blob = html.Blob([bytes]);
  formData.appendBlob('file', blob, filename);
  if (password != null && password.isNotEmpty) {
    formData.append('password', password);
  }

  int lastReportTime = 0;
  final totalBytes = bytes.length;

  xhr.upload.onProgress.listen((html.ProgressEvent event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sent = event.loaded ?? 0;
    final total = (event.total != null && event.total! > 0) ? event.total! : totalBytes;

    // Report at 600ms throttle or when 100% reached
    if (sent >= total) {
      if (onProgress != null) {
        onProgress(total, total);
      }
      if (onAnalyzing != null) {
        onAnalyzing();
      }
    } else if (now - lastReportTime >= 600) {
      lastReportTime = now;
      if (onProgress != null) {
        onProgress(sent, total);
      }
    }
  });

  xhr.onLoad.listen((_) {
    final status = xhr.status ?? 0;
    final responseText = xhr.responseText ?? '';
    try {
      final json = jsonDecode(responseText) as Map<String, dynamic>;
      completer.complete({'statusCode': status, 'data': json});
    } catch (_) {
      completer.complete({
        'statusCode': status,
        'data': {'detail': responseText.isNotEmpty ? responseText : 'HTTP $status'}
      });
    }
  });

  xhr.onError.listen((_) {
    completer.complete({
      'statusCode': xhr.status ?? 500,
      'data': {'detail': 'Network error during document transmission.'}
    });
  });

  xhr.send(formData);

  return completer.future;
}

/// Native browser XMLHttpRequest uploader for all PDF Suite tools.
/// Features true socket upload progress polled every 600 milliseconds,
/// supports binary arraybuffer responses (PDF, ZIP), and multi-file form payloads.
Future<ToolUploadResponse> executeToolUploadWithProgress({
  required String url,
  required List<UploadFileItem> files,
  Map<String, String>? fields,
  Map<String, String>? headers,
  Function(int sentBytes, int totalBytes)? onProgress,
  Duration pollInterval = const Duration(milliseconds: 600),
}) {
  final completer = Completer<ToolUploadResponse>();
  final xhr = html.HttpRequest();

  xhr.open('POST', url);
  xhr.responseType = 'arraybuffer';

  if (headers != null) {
    headers.forEach((key, value) {
      xhr.setRequestHeader(key, value);
    });
  }

  final formData = html.FormData();
  for (final file in files) {
    final blob = html.Blob([file.bytes]);
    formData.appendBlob(file.fieldName, blob, file.filename);
  }

  if (fields != null) {
    fields.forEach((key, value) {
      formData.append(key, value);
    });
  }

  int currentSent = 0;
  int totalBytes = files.fold<int>(0, (sum, f) => sum + f.bytes.length);
  if (totalBytes <= 0) totalBytes = 1;

  // Active polling timer at requested 600ms cadence
  Timer? pollTimer;
  pollTimer = Timer.periodic(pollInterval, (_) {
    if (onProgress != null && currentSent < totalBytes) {
      onProgress(currentSent, totalBytes);
    }
  });

  xhr.upload.onProgress.listen((html.ProgressEvent event) {
    currentSent = event.loaded ?? currentSent;
    if (event.total != null && event.total! > 0) {
      totalBytes = event.total!;
    }
    if (currentSent >= totalBytes) {
      pollTimer?.cancel();
      if (onProgress != null) {
        onProgress(totalBytes, totalBytes);
      }
    }
  });

  xhr.onLoad.listen((_) {
    pollTimer?.cancel();
    if (onProgress != null) {
      onProgress(totalBytes, totalBytes);
    }

    final status = xhr.status ?? 0;
    Uint8List responseBytes = Uint8List(0);
    String responseString = '';

    if (xhr.response != null) {
      if (xhr.response is ByteBuffer) {
        responseBytes = (xhr.response as ByteBuffer).asUint8List();
        responseString = utf8.decode(responseBytes, allowMalformed: true);
      } else if (xhr.response is Uint8List) {
        responseBytes = xhr.response as Uint8List;
        responseString = utf8.decode(responseBytes, allowMalformed: true);
      } else {
        responseString = xhr.responseText ?? '';
        responseBytes = Uint8List.fromList(utf8.encode(responseString));
      }
    }

    completer.complete(ToolUploadResponse(
      statusCode: status,
      bodyBytes: responseBytes,
      bodyString: responseString,
      headers: xhr.responseHeaders,
    ));
  });

  xhr.onError.listen((_) {
    pollTimer?.cancel();
    completer.complete(ToolUploadResponse(
      statusCode: xhr.status ?? 500,
      bodyBytes: Uint8List(0),
      bodyString: 'Network error during upload transmission.',
      headers: {},
    ));
  });

  xhr.send(formData);

  return completer.future;
}
