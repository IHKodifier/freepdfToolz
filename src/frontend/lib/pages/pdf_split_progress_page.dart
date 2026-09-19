import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/adsense_banner.dart';
import '../utils/app_limits_config.dart';
import '../services/telemetry_service.dart';
import '../services/download_helper.dart';
import '../services/api_service.dart';
import '../services/pdf_thumbnail_service.dart';
import '../widgets/tool_upload_progress_indicator.dart';
import 'pdf_merge_page.dart' show SelectedPdfFile;

/// Dedicated Status & Progress Page for PDF Split (/split/process)
///
/// Ad Monetization Architecture:
/// - Dedicated route for Ad #2 (GAM 60s rotation).
/// - Dynamic page range parsing, fixed interval stepping, and 1-click all-page extraction.
/// - In-memory client download for instant output retrieval.
class PdfSplitProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfSplitProgressPage({super.key, this.file});

  @override
  State<PdfSplitProgressPage> createState() => _PdfSplitProgressPageState();
}

class _PdfSplitProgressPageState extends State<PdfSplitProgressPage> {
  SelectedPdfFile? _file;
  int _detectedPages = 1;

  // Split Modes: 'ranges', 'fixed', 'all'
  String _mode = 'ranges';
  late final TextEditingController _rangesController;
  int _splitEvery = 2;

  bool _isSplitting = false;
  bool _isUploading = false;
  int _uploadSentBytes = 0;
  int _uploadTotalBytes = 0;
  String? _errorMessage;
  String? _validationWarning;
  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnail = false;
  bool _isUploadingThumbnail = false;
  int _thumbnailSentBytes = 0;
  int _thumbnailTotalBytes = 0;

  // Split result
  Uint8List? _resultBytes;
  String? _resultFilename;
  String? _resultMimeType;

  @override
  void initState() {
    super.initState();
    _file = widget.file;

    _rangesController = TextEditingController();
    _rangesController.addListener(_validateRangesLive);

    TelemetryService.trackPageView(
      '/split/process',
      pageTitle: 'FreePDFToolz — Split PDF',
    );
    AppLimitsConfig.ensureLoaded();

    if (_file != null) {
      _initDocumentState(_file!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_file == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
        _file = args['file'] as SelectedPdfFile;
        _initDocumentState(_file!);
      }
    }
  }

  void _initDocumentState(SelectedPdfFile file) {
    _detectedPages = _detectPageCount(file.bytes);
    if (_detectedPages > 1) {
      final half = (_detectedPages / 2).ceil();
      _rangesController.text = '1-$half';
    } else {
      _rangesController.text = '1';
    }
    _validateRangesLive();
    _loadThumbnail(file);
  }

  Future<void> _loadThumbnail(SelectedPdfFile file) async {
    setState(() {
      _isLoadingThumbnail = true;
      _isUploadingThumbnail = true;
      _thumbnailSentBytes = 0;
      _thumbnailTotalBytes = file.sizeBytes;
    });
    final result = await PdfThumbnailService.fetchThumbnails(
      file,
      onProgress: (sent, total) {
        if (mounted) {
          setState(() {
            _thumbnailSentBytes = sent;
            _thumbnailTotalBytes = total;
            if (sent >= total) {
              _isUploadingThumbnail = false;
            }
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _thumbnailResult = result;
      _isLoadingThumbnail = false;
      _isUploadingThumbnail = false;
      if (result.isSuccess && result.totalPages > 0) {
        _detectedPages = result.totalPages;
      }
    });
  }

  @override
  void dispose() {
    _rangesController.dispose();
    super.dispose();
  }

  int _detectPageCount(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return 1;
    try {
      final text = String.fromCharCodes(bytes);
      final countMatches = RegExp(r'/Count\s+(\d+)').allMatches(text);
      int maxFound = 0;
      for (final m in countMatches) {
        final val = int.tryParse(m.group(1) ?? '0') ?? 0;
        if (val > maxFound) maxFound = val;
      }
      if (maxFound > 0) return maxFound;
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(text);
      if (pageMatches.isNotEmpty) return pageMatches.length;
    } catch (_) {}
    return 1;
  }

  void _validateRangesLive() {
    final text = _rangesController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _validationWarning = 'Please enter at least one page range (e.g. 1-2, 4).';
      });
      return;
    }

    final chunks = text.split(',');
    for (final raw in chunks) {
      final chunk = raw.trim();
      if (chunk.isEmpty) continue;

      if (chunk.contains('-')) {
        final parts = chunk.split('-');
        if (parts.length != 2) {
          setState(() {
            _validationWarning = "Invalid format '$chunk'. Use format 'start-end'.";
          });
          return;
        }
        final start = int.tryParse(parts[0].trim());
        final end = int.tryParse(parts[1].trim());
        if (start == null || end == null) {
          setState(() {
            _validationWarning = "Page numbers must be integers in '$chunk'.";
          });
          return;
        }
        if (start < 1 || end < 1) {
          setState(() {
            _validationWarning = 'Page numbers must be 1 or greater.';
          });
          return;
        }
        if (start > end) {
          setState(() {
            _validationWarning = "Start page ($start) cannot be greater than end page ($end).";
          });
          return;
        }
        if (start > _detectedPages || end > _detectedPages) {
          setState(() {
            _validationWarning = "Page range '$chunk' exceeds document page count ($_detectedPages).";
          });
          return;
        }
      } else {
        final pageNum = int.tryParse(chunk);
        if (pageNum == null) {
          setState(() {
            _validationWarning = "Invalid page number '$chunk'.";
          });
          return;
        }
        if (pageNum < 1) {
          setState(() {
            _validationWarning = 'Page numbers must be 1 or greater.';
          });
          return;
        }
        if (pageNum > _detectedPages) {
          setState(() {
            _validationWarning = "Page $pageNum exceeds document page count ($_detectedPages).";
          });
          return;
        }
      }
    }

    setState(() {
      _validationWarning = null;
    });
  }

  Future<void> _executeSplit() async {
    if (_file == null || _file!.bytes == null) return;
    if (_mode == 'ranges' && _validationWarning != null) return;

    final totalBytes = _file!.bytes!.length;
    setState(() {
      _isSplitting = true;
      _isUploading = true;
      _uploadSentBytes = 0;
      _uploadTotalBytes = totalBytes;
      _errorMessage = null;
    });

    try {
      final fields = <String, String>{'mode': _mode};
      if (_mode == 'ranges') {
        fields['ranges'] = _rangesController.text.trim();
      } else if (_mode == 'fixed') {
        fields['split_every'] = _splitEvery.toString();
      }

      final response = await ApiService.uploadToolFiles(
        endpoint: '/tools/split',
        files: [
          UploadFileItem(
            fieldName: 'file',
            filename: _file!.name,
            bytes: _file!.bytes!,
          ),
        ],
        fields: fields,
        onProgress: (sent, total) {
          if (mounted) {
            setState(() {
              _uploadSentBytes = sent;
              _uploadTotalBytes = total;
              if (sent >= total) {
                _isUploading = false;
              }
            });
          }
        },
      );

      if (response.isSuccess) {
        final contentType = response.headers['content-type'] ?? 'application/pdf';
        final isZip = contentType.contains('zip');
        final defaultName = isZip
            ? '${_file!.name.replaceAll('.pdf', '')}_split.zip'
            : '${_file!.name.replaceAll('.pdf', '')}_split.pdf';

        String downloadName = defaultName;
        final disposition = response.headers['content-disposition'];
        if (disposition != null && disposition.contains('filename=')) {
          final regex = RegExp(r'filename=["' + "'" + r']?([^"' + "'" + r';\r\n]+)');
          final match = regex.firstMatch(disposition);
          if (match != null && match.group(1) != null) {
            downloadName = match.group(1)!.trim();
          }
        }

        setState(() {
          _resultBytes = response.bodyBytes;
          _resultFilename = downloadName;
          _resultMimeType = isZip ? 'application/zip' : 'application/pdf';
          _isSplitting = false;
          _isUploading = false;
        });

        TelemetryService.trackEvent('pdf_split_completed', {
          'mode': _mode,
          'output_size_bytes': response.bodyBytes.length,
          'filename': downloadName,
        });
      } else {
        String detail = 'Split operation failed (HTTP ${response.statusCode})';
        try {
          final decoded = jsonDecode(response.bodyString);
          if (decoded['detail'] != null) detail = decoded['detail'];
        } catch (_) {
          if (response.bodyString.isNotEmpty) detail = response.bodyString;
        }
        setState(() {
          _errorMessage = detail;
          _isSplitting = false;
          _isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error during split operation: $e';
        _isSplitting = false;
        _isUploading = false;
      });
    }
  }

  void _downloadResult() {
    if (_resultBytes == null || _resultFilename == null) return;
    TelemetryService.trackDownloadClicked(
      jobId: 'split_${DateTime.now().millisecondsSinceEpoch}',
      format: _resultMimeType?.contains('zip') == true ? 'zip' : 'pdf',
      filename: _resultFilename!,
    );
    DownloadHelper.triggerDownloadBytes(
      _resultBytes!,
      _resultFilename!,
      _resultMimeType ?? 'application/pdf',
    );
  }

  void _resetAndGoBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/split');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_file == null) {
      return Scaffold(
        appBar: const AppHeader(currentRoute: '/split'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No PDF file selected.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _resetAndGoBack,
                child: const Text('Go to Split Tool'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      appBar: const AppHeader(currentRoute: '/split'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 960),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                // AdSense Banner #2 (Status/Progress route with declared 60s rotation)
                const AdSenseBanner(),
                const SizedBox(height: 24),

                // Navigation Back & Title Row
                Row(
                  children: [
                    IconButton(
                      onPressed: _resetAndGoBack,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Choose another file',
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Split PDF Document',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Document Overview Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161B22) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 62,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildThumbnailPreview(isDark),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _file!.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$_detectedPages Pages',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? const Color(0xFF58A6FF) : const Color(0xFF0969DA),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _file!.formattedSize,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _resetAndGoBack,
                        icon: const Icon(Icons.close),
                        tooltip: 'Change Document',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (_isLoadingThumbnail) ...[
                  ToolUploadProgressIndicator(
                    sentBytes: _thumbnailSentBytes,
                    totalBytes: _thumbnailTotalBytes,
                    isUploading: _isUploadingThumbnail,
                    processingLabel: 'Generating page thumbnails...',
                    accentColor: const Color(0xFF0969DA),
                  ),
                ],

                // If result is ready, display Download Card
                if (_resultBytes != null) ...[
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF161B22) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF2EA043).withOpacity(0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2EA043).withOpacity(0.1),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2EA043).withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            size: 40,
                            color: Color(0xFF2EA043),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Split Completed Successfully!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _resultFilename ?? 'download',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _downloadResult,
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            'Download ${_resultFilename?.endsWith('.zip') == true ? 'ZIP Archive' : 'PDF'}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2EA043),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _resultBytes = null;
                              _resultFilename = null;
                              _resultMimeType = null;
                            });
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Split Again With Different Settings'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  // Mode Selector Card
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF161B22) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose Split Mode',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Mode Selector Chips
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            ChoiceChip(
                              key: const Key('mode_ranges_chip'),
                              label: const Text('Custom Ranges'),
                              selected: _mode == 'ranges',
                              onSelected: (val) {
                                setState(() => _mode = 'ranges');
                              },
                              selectedColor: const Color(0xFF0969DA),
                              labelStyle: TextStyle(
                                color: _mode == 'ranges'
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            ChoiceChip(
                              key: const Key('mode_fixed_chip'),
                              label: const Text('Split Every N Pages'),
                              selected: _mode == 'fixed',
                              onSelected: (val) {
                                setState(() => _mode = 'fixed');
                              },
                              selectedColor: const Color(0xFF0969DA),
                              labelStyle: TextStyle(
                                color: _mode == 'fixed'
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            ChoiceChip(
                              key: const Key('mode_all_chip'),
                              label: const Text('Extract All Pages'),
                              selected: _mode == 'all',
                              onSelected: (val) {
                                setState(() => _mode = 'all');
                              },
                              selectedColor: const Color(0xFF0969DA),
                              labelStyle: TextStyle(
                                color: _mode == 'all'
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Divider(height: 1),
                        const SizedBox(height: 20),

                        // Mode A: Custom Ranges UI
                        if (_mode == 'ranges') ...[
                          Text(
                            'Page Ranges to Extract',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _rangesController,
                            decoration: InputDecoration(
                              hintText: 'e.g. 1-2, 5, 7-10',
                              filled: true,
                              fillColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: _validationWarning != null
                                      ? Colors.orangeAccent
                                      : (isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1)),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_validationWarning != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                _validationWarning!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                          else
                            Text(
                              'Specify individual pages or page ranges separated by commas. e.g. 1-3, 5',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                              ),
                            ),
                        ],

                        // Mode B: Fixed Interval Stepper UI
                        if (_mode == 'fixed') ...[
                          Text(
                            'Split Interval',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'Split every',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 18),
                                      onPressed: _splitEvery > 1
                                          ? () => setState(() => _splitEvery--)
                                          : null,
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    ),
                                    Container(
                                      constraints: const BoxConstraints(minWidth: 40),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$_splitEvery',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 18),
                                      onPressed: _splitEvery < _detectedPages
                                          ? () => setState(() => _splitEvery++)
                                          : null,
                                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                'pages',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Will generate ${(_detectedPages / _splitEvery).ceil()} separate PDF documents.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                            ),
                          ),
                        ],

                        // Mode C: Extract All Pages UI
                        if (_mode == 'all') ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0969DA).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF0969DA).withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Color(0xFF0969DA),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Extract all $_detectedPages pages into individual single-page PDFs packaged in a ZIP archive.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 28),

                        if (_isSplitting) ...[
                          ToolUploadProgressIndicator(
                            sentBytes: _uploadSentBytes,
                            totalBytes: _uploadTotalBytes,
                            isUploading: _isUploading,
                            processingLabel: 'Splitting PDF Document...',
                            accentColor: const Color(0xFF0969DA),
                          ),
                        ],

                        // Split PDF Submit Action Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSplitting ||
                                    (_mode == 'ranges' && _validationWarning != null)
                                ? null
                                : _executeSplit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0969DA),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            child: _isSplitting
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        _isUploading
                                            ? 'Uploading PDF (${(_uploadTotalBytes > 0 ? (_uploadSentBytes / _uploadTotalBytes * 100).toInt() : 0)}%)...'
                                            : 'Splitting PDF...',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Text(
                                    'Split PDF',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const AppFooter(currentRoute: '/split/process'),
      ],
    ),
  ),
);
  }

  Widget _buildThumbnailPreview(bool isDark) {
    final bytes = _thumbnailResult?.getPageBytes(0);
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
      );
    }
    if (_isLoadingThumbnail) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0969DA)),
          ),
        ),
      );
    }
    return Container(
      color: const Color(0xFF0969DA).withOpacity(0.12),
      child: const Center(
        child: Icon(
          Icons.picture_as_pdf_rounded,
          color: Color(0xFF0969DA),
          size: 24,
        ),
      ),
    );
  }
}
