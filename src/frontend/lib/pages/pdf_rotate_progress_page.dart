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

/// Dedicated Status & Progress Page for PDF Rotate (/rotate/process)
///
/// Ad Monetization Architecture:
/// - Dedicated route for Ad #2 (GAM 60s rotation).
/// - Visual interactive page preview grid with animated rotations.
/// - In-memory client download for instant output retrieval.
class PdfRotateProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfRotateProgressPage({super.key, this.file});

  @override
  State<PdfRotateProgressPage> createState() => _PdfRotateProgressPageState();
}

class _PdfRotateProgressPageState extends State<PdfRotateProgressPage> {
  SelectedPdfFile? _file;
  int _detectedPages = 1;
  final Map<int, int> _pageRotations = {}; // index -> angle (0, 90, 180, 270)
  bool _isSaving = false;
  bool _isUploading = false;
  int _uploadSentBytes = 0;
  int _uploadTotalBytes = 0;
  String? _errorMessage;
  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnails = false;
  bool _isUploadingThumbnails = false;
  int _thumbnailSentBytes = 0;
  int _thumbnailTotalBytes = 0;
  double _zoomLevel = 1.0;

  // Rotation result
  Uint8List? _resultBytes;
  String? _resultFilename;

  @override
  void initState() {
    super.initState();
    _file = widget.file;

    TelemetryService.trackPageView(
      '/rotate/process',
      pageTitle: 'FreePDFToolz — Rotate PDF',
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
    _pageRotations.clear();
    for (int i = 0; i < _detectedPages; i++) {
      _pageRotations[i] = 0;
    }
    if (mounted) setState(() {});
    _loadThumbnails(file);
  }

  Future<void> _loadThumbnails(SelectedPdfFile file) async {
    setState(() {
      _isLoadingThumbnails = true;
      _isUploadingThumbnails = true;
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
              _isUploadingThumbnails = false;
            }
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _thumbnailResult = result;
      _isLoadingThumbnails = false;
      _isUploadingThumbnails = false;
      if (result.isSuccess && result.totalPages > 0) {
        _detectedPages = result.totalPages;
        for (int i = 0; i < _detectedPages; i++) {
          _pageRotations.putIfAbsent(i, () => 0);
        }
      }
    });
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

  void _rotatePage(int index, int delta) {
    setState(() {
      final current = _pageRotations[index] ?? 0;
      _pageRotations[index] = (current + delta) % 360;
      if (_pageRotations[index]! < 0) {
        _pageRotations[index] = _pageRotations[index]! + 360;
      }
    });
  }

  void _rotateAll(int delta) {
    setState(() {
      for (int i = 0; i < _detectedPages; i++) {
        final current = _pageRotations[i] ?? 0;
        var next = (current + delta) % 360;
        if (next < 0) next += 360;
        _pageRotations[i] = next;
      }
    });
  }

  void _resetAll() {
    setState(() {
      for (int i = 0; i < _detectedPages; i++) {
        _pageRotations[i] = 0;
      }
    });
  }

  Future<void> _executeRotate() async {
    if (_file == null || _file!.bytes == null) return;

    setState(() {
      _isSaving = true;
      _isUploading = true;
      _uploadSentBytes = 0;
      _uploadTotalBytes = _file!.bytes!.length;
      _errorMessage = null;
    });

    try {
      // Map of string page indices to rotation angles
      final rotationsPayload = <String, int>{};
      _pageRotations.forEach((idx, angle) {
        if (angle != 0) {
          rotationsPayload[idx.toString()] = angle;
        }
      });

      final uploadRes = await ApiService.uploadToolFiles(
        endpoint: '/tools/rotate',
        fields: {
          'rotations': jsonEncode(rotationsPayload),
        },
        files: [
          UploadFileItem(
            field: 'file',
            filename: _file!.name,
            bytes: _file!.bytes!,
          ),
        ],
        onProgress: (sent, total) {
          if (mounted) {
            setState(() {
              _uploadSentBytes = sent;
              _uploadTotalBytes = total;
              if (sent >= total && total > 0) {
                _isUploading = false;
              }
            });
          }
        },
      );

      if (uploadRes.statusCode == 200) {
        final defaultName = '${_file!.name.replaceAll('.pdf', '')}_rotated.pdf';
        final downloadName = uploadRes.filename ?? defaultName;

        setState(() {
          _resultBytes = uploadRes.bytes;
          _resultFilename = downloadName;
          _isSaving = false;
          _isUploading = false;
        });

        TelemetryService.trackEvent('pdf_rotate_completed', {
          'modified_pages_count': rotationsPayload.length,
          'total_pages': _detectedPages,
          'output_size_bytes': uploadRes.bytes.length,
          'filename': downloadName,
        });
      } else {
        String detail = 'Rotate operation failed (HTTP ${uploadRes.statusCode})';
        try {
          final decoded = jsonDecode(utf8.decode(uploadRes.bytes));
          if (decoded['detail'] != null) detail = decoded['detail'];
        } catch (_) {}
        setState(() {
          _errorMessage = detail;
          _isSaving = false;
          _isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error during rotate operation: $e';
        _isSaving = false;
        _isUploading = false;
      });
    }
  }

  void _downloadResult() {
    if (_resultBytes == null || _resultFilename == null) return;
    TelemetryService.trackDownloadClicked(
      jobId: 'rotate_${DateTime.now().millisecondsSinceEpoch}',
      format: 'pdf',
      filename: _resultFilename!,
    );
    DownloadHelper.triggerDownloadBytes(
      _resultBytes!,
      _resultFilename!,
      'application/pdf',
    );
  }

  void _resetAndGoBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/rotate');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_file == null) {
      return Scaffold(
        appBar: const AppHeader(currentRoute: '/rotate'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No PDF file selected.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _resetAndGoBack,
                child: const Text('Go to Rotate Tool'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      appBar: const AppHeader(currentRoute: '/rotate'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1040),
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
                          'Rotate PDF Pages',
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
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0969DA).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Color(0xFF0969DA),
                              size: 28,
                            ),
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
                              'Rotation Applied Successfully!',
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
                              label: const Text(
                                'Download Rotated PDF',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Rotate Again With Different Angles'),
                            ),
                            const SizedBox(height: 20),
                            const AdSenseBanner(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      // Global Rotation Toolbar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF161B22) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _rotateAll(-90),
                                  icon: const Icon(Icons.rotate_left_rounded, size: 18),
                                  label: const Text('Rotate All Left (-90°)'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: isDark ? Colors.white70 : const Color(0xFF1E293B),
                                    side: BorderSide(
                                      color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _rotateAll(90),
                                  icon: const Icon(Icons.rotate_right_rounded, size: 18),
                                  label: const Text('Rotate All Right (+90°)'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: isDark ? Colors.white70 : const Color(0xFF1E293B),
                                    side: BorderSide(
                                      color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _resetAll,
                                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                                  label: const Text('Reset All'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                // Universal Zoom Controls
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        key: const Key('zoom_out_btn'),
                                        icon: const Icon(Icons.remove_rounded, size: 16),
                                        tooltip: 'Zoom Out',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        onPressed: _zoomLevel > 0.75
                                            ? () => setState(() => _zoomLevel = (_zoomLevel - 0.25).clamp(0.75, 2.0))
                                            : null,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Text(
                                          '${(_zoomLevel * 100).toInt()}%',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        key: const Key('zoom_in_btn'),
                                        icon: const Icon(Icons.add_rounded, size: 16),
                                        tooltip: 'Zoom In',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        onPressed: _zoomLevel < 2.0
                                            ? () => setState(() => _zoomLevel = (_zoomLevel + 0.25).clamp(0.75, 2.0))
                                            : null,
                                      ),
                                      if (_zoomLevel != 1.0)
                                        IconButton(
                                          icon: const Icon(Icons.restart_alt_rounded, size: 16),
                                          tooltip: 'Reset Zoom (100%)',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          onPressed: () => setState(() => _zoomLevel = 1.0),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'Click thumbnails or arrows to orient',
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
                      const SizedBox(height: 24),

                      if (_isLoadingThumbnails) ...[
                        ToolUploadProgressIndicator(
                          sentBytes: _thumbnailSentBytes,
                          totalBytes: _thumbnailTotalBytes,
                          isUploading: _isUploadingThumbnails,
                          processingLabel: 'Generating page thumbnails...',
                          accentColor: const Color(0xFF0969DA),
                        ),
                      ],

                      // Visual Page Preview Grid (Dynamically Scaled)
                      GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240 * _zoomLevel,
                          mainAxisExtent: 310 * _zoomLevel,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                        ),
                        itemCount: _detectedPages,
                        itemBuilder: (context, index) {
                          final angle = _pageRotations[index] ?? 0;
                          return _buildPageCard(
                            index: index,
                            angle: angle,
                            isDark: isDark,
                          );
                        },
                      ),
                      const SizedBox(height: 32),

                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      if (_isSaving) ...[
                        ToolUploadProgressIndicator(
                          isUploading: _isUploading,
                          sentBytes: _uploadSentBytes,
                          totalBytes: _uploadTotalBytes,
                          processingLabel: 'Rotating pages and compiling in RAM disk...',
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Action Button
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _executeRotate,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.check_circle_outline_rounded),
                        label: Text(
                          _isSaving
                              ? (_isUploading ? 'Uploading Document...' : 'Processing Rotation...')
                              : 'Save & Apply Rotation',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0969DA),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(height: 36),
                    ],
                  ],
                ),
              ),
            ),
            const AppFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildPageCard({
    required int index,
    required int angle,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: angle != 0
              ? const Color(0xFF0969DA)
              : (isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
          width: angle != 0 ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header: Page badge & Angle badge
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Page ${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: angle != 0
                        ? const Color(0xFF0969DA).withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$angle°',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: angle != 0
                          ? const Color(0xFF0969DA)
                          : (isDark ? const Color(0xFF8B949E) : const Color(0xFF94A3B8)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Central Page Thumbnail Preview with AnimatedRotation
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Center(
                child: AnimatedRotation(
                  turns: angle / 360.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: Container(
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
                    child: _buildThumbnailContent(index, angle, isDark),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Controls: Rotate Left (-90°) and Rotate Right (+90°)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117).withOpacity(0.5) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  key: Key('rotate_left_page_$index'),
                  icon: const Icon(Icons.rotate_left_rounded, size: 20),
                  tooltip: 'Rotate Left (-90°)',
                  onPressed: () => _rotatePage(index, -90),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
                IconButton(
                  key: Key('rotate_right_page_$index'),
                  icon: const Icon(Icons.rotate_right_rounded, size: 20),
                  tooltip: 'Rotate Right (+90°)',
                  onPressed: () => _rotatePage(index, 90),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                  color: const Color(0xFF0969DA),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailContent(int index, int angle, bool isDark) {
    final bytes = _thumbnailResult?.getPageBytes(index);
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildFallbackPlaceholder(angle, isDark),
      );
    }

    if (_isLoadingThumbnails) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              angle != 0
                  ? const Color(0xFF0969DA)
                  : (isDark ? const Color(0xFF8B949E) : const Color(0xFF94A3B8)),
            ),
          ),
        ),
      );
    }

    return _buildFallbackPlaceholder(angle, isDark);
  }

  Widget _buildFallbackPlaceholder(int angle, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.description_outlined,
          size: 38,
          color: angle != 0
              ? const Color(0xFF0969DA)
              : (isDark ? const Color(0xFF8B949E) : const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 8),
        Container(
          width: 48,
          height: 3,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 32,
          height: 3,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}
