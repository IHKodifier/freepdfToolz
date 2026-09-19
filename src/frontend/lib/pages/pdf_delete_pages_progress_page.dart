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

/// Dedicated Status & Progress Page for PDF Delete Pages (/delete-pages/process)
///
/// Ad Monetization Architecture:
/// - Dedicated route for Ad #2 (GAM 60s rotation).
/// - Visual interactive page deletion grid with instant toggle.
/// - Retention guard: prevents 100% page deletion both in UI and backend.
/// - In-memory client download for instant output retrieval with Ad #3.
class PdfDeletePagesProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfDeletePagesProgressPage({super.key, this.file});

  @override
  State<PdfDeletePagesProgressPage> createState() => _PdfDeletePagesProgressPageState();
}

class _PdfDeletePagesProgressPageState extends State<PdfDeletePagesProgressPage> {
  SelectedPdfFile? _file;
  int _detectedPages = 1;
  final Set<int> _deletedPageIndices = {};
  double _zoomLevel = 1.0;

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

  // Pruning result
  Uint8List? _resultBytes;
  String? _resultFilename;

  @override
  void initState() {
    super.initState();
    _file = widget.file;

    TelemetryService.trackPageView(
      '/delete-pages/process',
      pageTitle: 'FreePDFToolz — Delete Pages',
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
    _deletedPageIndices.clear();
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
      onBatchLoaded: (allPages, totalPages) {
        if (mounted) {
          setState(() {
            _detectedPages = totalPages;
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

  void _togglePage(int index) {
    setState(() {
      if (_deletedPageIndices.contains(index)) {
        _deletedPageIndices.remove(index);
      } else {
        _deletedPageIndices.add(index);
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (int i = 0; i < _detectedPages; i++) {
        _deletedPageIndices.add(i);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _deletedPageIndices.clear();
    });
  }

  void _invertSelection() {
    setState(() {
      for (int i = 0; i < _detectedPages; i++) {
        if (_deletedPageIndices.contains(i)) {
          _deletedPageIndices.remove(i);
        } else {
          _deletedPageIndices.add(i);
        }
      }
    });
  }

  Future<void> _executeDelete() async {
    if (_file == null || _file!.bytes == null) return;
    if (_deletedPageIndices.isEmpty || _deletedPageIndices.length >= _detectedPages) return;

    final sessionFileId = _thumbnailResult?.sessionFileId;
    final bool useStagedFile = sessionFileId != null && sessionFileId.isNotEmpty;
    final totalBytes = useStagedFile ? 1 : _file!.bytes!.length;
    setState(() {
      _isSaving = true;
      _isUploading = true;
      _uploadSentBytes = 0;
      _uploadTotalBytes = totalBytes;
      _errorMessage = null;
    });

    try {
      final pagesList = _deletedPageIndices.toList()..sort();
      final fields = <String, String>{
        'pages': jsonEncode(pagesList),
      };
      final List<UploadFileItem> files = [];
      if (useStagedFile) {
        fields['session_file_id'] = sessionFileId;
      } else {
        files.add(
          UploadFileItem(
            fieldName: 'file',
            filename: _file!.name,
            bytes: _file!.bytes!,
          ),
        );
      }

      final response = await ApiService.uploadToolFiles(
        endpoint: '/tools/delete-pages',
        files: files,
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
        final defaultName = '${_file!.name.replaceAll('.pdf', '')}_pruned.pdf';
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
          _isSaving = false;
          _isUploading = false;
        });

        TelemetryService.trackEvent('pdf_delete_pages_completed', {
          'deleted_pages_count': pagesList.length,
          'remaining_pages_count': _detectedPages - pagesList.length,
          'total_pages': _detectedPages,
          'output_size_bytes': response.bodyBytes.length,
          'filename': downloadName,
        });
      } else {
        String detail = 'Delete operation failed (HTTP ${response.statusCode})';
        try {
          final decoded = jsonDecode(response.bodyString);
          if (decoded['detail'] != null) detail = decoded['detail'];
        } catch (_) {
          if (response.bodyString.isNotEmpty) detail = response.bodyString;
        }
        setState(() {
          _errorMessage = detail;
          _isSaving = false;
          _isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error during delete operation: $e';
        _isSaving = false;
        _isUploading = false;
      });
    }
  }

  void _downloadResult() {
    if (_resultBytes == null || _resultFilename == null) return;
    TelemetryService.trackDownloadClicked(
      jobId: 'delete_${DateTime.now().millisecondsSinceEpoch}',
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
      Navigator.pushReplacementNamed(context, '/delete-pages');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_file == null) {
      return Scaffold(
        appBar: const AppHeader(currentRoute: '/delete-pages'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No PDF file selected.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _resetAndGoBack,
                child: const Text('Go to Delete Pages Tool'),
              ),
            ],
          ),
        ),
      );
    }

    final isAllSelected = _deletedPageIndices.length >= _detectedPages;
    final isNoneSelected = _deletedPageIndices.isEmpty;
    final remainingCount = _detectedPages - _deletedPageIndices.length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      appBar: const AppHeader(currentRoute: '/delete-pages'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1040),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // AdSense Banner #2 (Dedicated workspace GAM 60s refresh)
                    const AdSenseBanner(),
                    const SizedBox(height: 28),

                    // Top Document Overview Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161B22) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
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
                              color: const Color(0xFFCF222E).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Color(0xFFCF222E),
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
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                  maxLines: 1,
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
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _formatFileSize(_file!.sizeBytes),
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
                          OutlinedButton.icon(
                            onPressed: _resetAndGoBack,
                            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                            label: const Text('Change File'),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_resultBytes != null) ...[
                      // Success / Download Result Card with Ad #3
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF161B22) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF2EA043), width: 1.5),
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
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 48,
                              color: Color(0xFF2EA043),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'PDF Pages Deleted Successfully!',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Pruned document contains $remainingCount pages (${_formatFileSize(_resultBytes!.length)})',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // AdSense Banner #3 (Download view)
                            const AdSenseBanner(),
                            const SizedBox(height: 24),

                            Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _downloadResult,
                                  icon: const Icon(Icons.download_rounded),
                                  label: Text('Download ${_resultFilename ?? "Pruned PDF"}'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2EA043),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _resultBytes = null;
                                      _resultFilename = null;
                                      _deletedPageIndices.clear();
                                    });
                                  },
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Delete More Pages'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      if (_isLoadingThumbnails) ...[
                        ToolUploadProgressIndicator(
                          sentBytes: _thumbnailSentBytes,
                          totalBytes: _thumbnailTotalBytes,
                          isUploading: _isUploadingThumbnails,
                          processingLabel: 'Generating page thumbnails...',
                          accentColor: const Color(0xFFCF222E),
                        ),
                      ],
                      if (!_isUploadingThumbnails) ...[
                        // Quick Action Toolbar & Status Bar
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
                                  onPressed: _selectAll,
                                  icon: const Icon(Icons.select_all_rounded, size: 18),
                                  label: const Text('Select All'),
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
                                  onPressed: _clearSelection,
                                  icon: const Icon(Icons.deselect_rounded, size: 18),
                                  label: const Text('Clear Selection'),
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
                                  onPressed: _invertSelection,
                                  icon: const Icon(Icons.swap_calls_rounded, size: 18),
                                  label: const Text('Invert'),
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
                                  '${_deletedPageIndices.length} of $_detectedPages pages marked to remove ($remainingCount pages will remain)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isAllSelected
                                        ? const Color(0xFFCF222E)
                                        : (isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (isAllSelected) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFCF222E).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCF222E).withOpacity(0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Color(0xFFCF222E), size: 22),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'A PDF must retain at least one page. You cannot delete all pages.',
                                  style: TextStyle(
                                    color: Color(0xFFCF222E),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Visual Page Preview Grid
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
                          final isDeleted = _deletedPageIndices.contains(index);
                          return _buildPageCard(
                            index: index,
                            isDeleted: isDeleted,
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
                          sentBytes: _uploadSentBytes,
                          totalBytes: _uploadTotalBytes,
                          isUploading: _isUploading,
                          processingLabel: 'Deleting Selected Pages in RAM disk...',
                          accentColor: const Color(0xFFCF222E),
                        ),
                      ],

                      // Action Button
                      ElevatedButton.icon(
                        onPressed: (_isSaving || isAllSelected || isNoneSelected)
                            ? null
                            : _executeDelete,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.delete_sweep_rounded),
                        label: Text(
                          _isSaving
                              ? (_isUploading
                                  ? 'Uploading PDF (${(_uploadTotalBytes > 0 ? (_uploadSentBytes / _uploadTotalBytes * 100).toInt() : 0)}%)...'
                                  : 'Deleting Selected Pages...')
                              : 'Delete Pages & Generate PDF',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFCF222E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                          disabledBackgroundColor: isDark
                              ? const Color(0xFF21262D)
                              : const Color(0xFFE2E8F0),
                          disabledForegroundColor: isDark
                              ? const Color(0xFF484F58)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 36),
                    ],
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
    required bool isDeleted,
    required bool isDark,
  }) {
    return InkWell(
      key: Key('page_card_$index'),
      onTap: () => _togglePage(index),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDeleted
                ? const Color(0xFFCF222E)
                : (isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
            width: isDeleted ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Opacity(
          opacity: isDeleted ? 0.45 : 1.0,
          child: Column(
            children: [
              // Card Header: Page Badge & Delete status tag
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
                    if (isDeleted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCF222E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DELETE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Card Body: Document Visual Thumbnail representation
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDeleted
                              ? const Color(0xFFCF222E).withOpacity(0.5)
                              : (isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1)),
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
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _buildThumbnailContent(index, isDeleted, isDark),
                          ),
                          if (isDeleted)
                            Positioned.fill(
                              child: Container(
                                color: const Color(0xFFCF222E).withOpacity(0.25),
                                child: const Center(
                                  child: Icon(
                                    Icons.delete_forever_rounded,
                                    size: 44,
                                    color: Color(0xFFCF222E),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Status Bar / Tap Hint
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D1117).withOpacity(0.5) : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
                  border: Border(
                    top: BorderSide(
                      color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isDeleted ? Icons.undo_rounded : Icons.delete_outline_rounded,
                          size: 15,
                          color: isDeleted
                              ? const Color(0xFFCF222E)
                              : (isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isDeleted ? 'Click to Restore' : 'Click to Delete',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDeleted
                                ? const Color(0xFFCF222E)
                                : (isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailContent(int index, bool isDeleted, bool isDark) {
    final bytes = _thumbnailResult?.getPageBytes(index);
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildFallbackPlaceholder(isDeleted, isDark),
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
              isDeleted
                  ? const Color(0xFFCF222E)
                  : (isDark ? const Color(0xFF8B949E) : const Color(0xFF94A3B8)),
            ),
          ),
        ),
      );
    }

    return _buildFallbackPlaceholder(isDeleted, isDark);
  }

  Widget _buildFallbackPlaceholder(bool isDeleted, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isDeleted ? Icons.delete_forever_rounded : Icons.description_outlined,
          size: 38,
          color: isDeleted
              ? const Color(0xFFCF222E)
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
