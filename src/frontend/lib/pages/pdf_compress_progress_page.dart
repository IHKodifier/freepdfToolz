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

/// Dedicated Status & Progress Page for PDF Compression (/compress/process)
///
/// Ad Monetization Architecture:
/// - Dedicated route for Ad #2 (GAM 60s rotation).
/// - 3 Selectable Compression Preset Cards (Recommended, Extreme, Low Lossless).
/// - Interactive comparison metric banner showing original vs compressed size and % saved.
/// - In-memory client download with Ad #3.
class PdfCompressProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfCompressProgressPage({super.key, this.file});

  @override
  State<PdfCompressProgressPage> createState() => _PdfCompressProgressPageState();
}

class _PdfCompressProgressPageState extends State<PdfCompressProgressPage> {
  SelectedPdfFile? _file;
  int _detectedPages = 1;

  // Compression configuration
  String _selectedLevel = 'recommended'; // 'recommended', 'extreme', 'low'

  bool _isCompressing = false;
  bool _isUploading = false;
  int _uploadSentBytes = 0;
  int _uploadTotalBytes = 0;
  String? _errorMessage;
  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnail = false;
  bool _isUploadingThumbnail = false;
  int _thumbnailSentBytes = 0;
  int _thumbnailTotalBytes = 0;

  // Compression Result Metrics
  Uint8List? _resultBytes;
  String? _resultFilename;
  int? _originalSizeBytes;
  int? _compressedSizeBytes;
  double? _percentSaved;

  @override
  void initState() {
    super.initState();
    _file = widget.file;

    TelemetryService.trackPageView(
      '/compress/process',
      pageTitle: 'FreePDFToolz — Compress PDF',
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
    _originalSizeBytes = file.sizeBytes;
    if (mounted) setState(() {});
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
      _isLoadingThumbnail = false;
      _isUploadingThumbnail = false;
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

  Future<void> _startCompression() async {
    if (_file == null || _file!.bytes == null) {
      setState(() {
        _errorMessage = 'No PDF document loaded for compression.';
      });
      return;
    }

    final sessionFileId = _thumbnailResult?.sessionFileId;
    final bool useStagedFile = sessionFileId != null && sessionFileId.isNotEmpty;
    final totalBytes = useStagedFile ? 1 : _file!.bytes!.length;

    setState(() {
      _isCompressing = true;
      _isUploading = true;
      _uploadSentBytes = 0;
      _uploadTotalBytes = totalBytes;
      _errorMessage = null;
      _resultBytes = null;
    });

    try {
      final fields = <String, String>{'level': _selectedLevel};
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
        endpoint: '/tools/compress',
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
        final cleanBase = _file!.name.replaceAll('.pdf', '');
        String downloadName = '${cleanBase}_compressed.pdf';

        final disposition = response.headers['content-disposition'];
        if (disposition != null && disposition.contains('filename=')) {
          final regex = RegExp(r'filename=["' "'" r']?([^"' "'" r';\r\n]+)');
          final match = regex.firstMatch(disposition);
          if (match != null && match.group(1) != null) {
            downloadName = match.group(1)!.trim();
          }
        }

        final origSize = int.tryParse(response.headers['x-original-size'] ?? '') ?? _file!.sizeBytes;
        final compSize = int.tryParse(response.headers['x-compressed-size'] ?? '') ?? response.bodyBytes.length;
        final pctSaved = double.tryParse(response.headers['x-percent-saved'] ?? '') ??
            (origSize > 0 ? ((origSize - compSize) / origSize) * 100.0 : 0.0);

        setState(() {
          _resultBytes = response.bodyBytes;
          _resultFilename = downloadName;
          _originalSizeBytes = origSize;
          _compressedSizeBytes = compSize;
          _percentSaved = pctSaved.clamp(0.0, 100.0);
          _isCompressing = false;
          _isUploading = false;
        });

        TelemetryService.trackEvent('pdf_compress_completed', {
          'level': _selectedLevel,
          'original_size': origSize,
          'compressed_size': compSize,
          'percent_saved': pctSaved,
          'filename': downloadName,
        });
      } else {
        String detail = 'Compression operation failed (HTTP ${response.statusCode})';
        try {
          final decoded = jsonDecode(response.bodyString);
          if (decoded['detail'] != null) detail = decoded['detail'];
        } catch (_) {
          if (response.bodyString.isNotEmpty) detail = response.bodyString;
        }
        setState(() {
          _errorMessage = detail;
          _isCompressing = false;
          _isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error during compression: $e';
        _isCompressing = false;
        _isUploading = false;
      });
    }
  }

  void _downloadResult() {
    if (_resultBytes == null || _resultFilename == null) return;
    TelemetryService.trackDownloadClicked(
      jobId: 'compress_${DateTime.now().millisecondsSinceEpoch}',
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
      Navigator.pushReplacementNamed(context, '/compress');
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

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const AppHeader(),

            // GAM 60s Auto-Refresh Ad Banner (Ad #2)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: AdSenseBanner(),
            ),

            Container(
              constraints: const BoxConstraints(maxWidth: 920),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Navigation Bar Back Link
                  InkWell(
                    onTap: _resetAndGoBack,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Back to Compress Tool',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Document Overview Card
                  if (_file != null) _buildDocumentOverviewCard(isDark),
                  const SizedBox(height: 24),

                  if (_isLoadingThumbnail) ...[
                    ToolUploadProgressIndicator(
                      sentBytes: _thumbnailSentBytes,
                      totalBytes: _thumbnailTotalBytes,
                      isUploading: _isUploadingThumbnail,
                      processingLabel: 'Generating page thumbnails...',
                    ),
                    const SizedBox(height: 20),
                  ],

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Configurator & Presets (Visible before compression completes)
                  if (_resultBytes == null && !_isUploadingThumbnail) ...[
                    Text(
                      'Select Compression Level',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose the balance between file size reduction and image quality.',
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 3 Preset Cards
                    _buildPresetCard(
                      key: const Key('preset_recommended'),
                      level: 'recommended',
                      title: 'Recommended Compression',
                      subtitle: 'Good quality, high compression (150 DPI) — ideal for most documents',
                      badge: 'RECOMMENDED',
                      badgeColor: Theme.of(context).colorScheme.primary,
                      icon: Icons.auto_awesome_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    _buildPresetCard(
                      key: const Key('preset_extreme'),
                      level: 'extreme',
                      title: 'Extreme Compression',
                      subtitle: 'Smallest file size, lower image quality (72 DPI) — ideal for emailing strict limits',
                      badge: 'MAX SAVINGS',
                      badgeColor: Colors.amber.shade700,
                      icon: Icons.compress_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    _buildPresetCard(
                      key: const Key('preset_low'),
                      level: 'low',
                      title: 'Low / Lossless Compression',
                      subtitle: 'Best visual quality, lossless streams & metadata cleanup — preserves original DPI',
                      badge: 'LOSSLESS',
                      badgeColor: Colors.green.shade600,
                      icon: Icons.high_quality_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 28),

                    if (_isCompressing) ...[
                      ToolUploadProgressIndicator(
                        sentBytes: _uploadSentBytes,
                        totalBytes: _uploadTotalBytes,
                        isUploading: _isUploading,
                        processingLabel: 'Compressing PDF Document...',
                      ),
                    ],

                    // Compress Button
                    Center(
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isCompressing ? null : _startCompression,
                          icon: _isCompressing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.compress_rounded),
                          label: Text(
                            _isCompressing
                                ? (_isUploading
                                    ? 'Uploading PDF (${(_uploadTotalBytes > 0 ? (_uploadSentBytes / _uploadTotalBytes * 100).toInt() : 0)}%)...'
                                    : 'Compressing PDF Document...')
                                : 'Compress PDF',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Results & Download Card (Visible after compression completes)
                  if (_resultBytes != null) ...[
                    _buildResultsComparisonBanner(isDark),
                    const SizedBox(height: 24),
                    _buildDownloadCard(isDark),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 40),
            const AppFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentOverviewCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$_detectedPages ${_detectedPages == 1 ? "Page" : "Pages"} • ${_formatFileSize(_file!.sizeBytes)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _resetAndGoBack,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Change File'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard({
    required Key key,
    required String level,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _selectedLevel == level;

    return InkWell(
      key: key,
      onTap: () {
        setState(() {
          _selectedLevel = level;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.05)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                    : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade500,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isSelected ? Theme.of(context).colorScheme.primary : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Radio<String>(
              value: level,
              groupValue: _selectedLevel,
              onChanged: (val) {
                if (val != null) setState(() => _selectedLevel = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsComparisonBanner(bool isDark) {
    final origText = _formatFileSize(_originalSizeBytes ?? 0);
    final compText = _formatFileSize(_compressedSizeBytes ?? 0);
    final pctText = (_percentSaved ?? 0.0).toStringAsFixed(1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade400.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
              const SizedBox(width: 10),
              Text(
                'PDF Successfully Compressed!',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.green.shade300 : Colors.green.shade800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Compressed from $origText to $compText (-$pctText%)',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your document is ready for instant download below.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _downloadResult,
              icon: const Icon(Icons.download_rounded),
              label: Text(
                'Download Compressed PDF (${_formatFileSize(_compressedSizeBytes ?? 0)})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _resetAndGoBack,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Compress Another PDF'),
          ),

          // Ad #3 in Download Area
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const AdSenseBanner(),
        ],
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
            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
          ),
        ),
      );
    }
    return Container(
      color: Colors.red.withValues(alpha: 0.1),
      child: const Center(
        child: Icon(Icons.picture_as_pdf, color: Colors.red, size: 24),
      ),
    );
  }
}
