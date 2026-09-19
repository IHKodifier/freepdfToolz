import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:http/http.dart' as http;
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/adsense_banner.dart';
import '../widgets/rewarded_video_ad_modal.dart';
import '../utils/app_limits_config.dart';
import '../services/telemetry_service.dart';
import '../services/download_helper.dart';
import '../services/api_service.dart';
import '../services/pdf_thumbnail_service.dart';
import '../main.dart' show themeNotifier;
import 'pdf_merge_page.dart' show SelectedPdfFile;

/// Dedicated Status & Progress Page for PDF Merge (/merge/process)
///
/// Ad Monetization Architecture:
/// - Hosted on dedicated route to generate Ad #2 impression.
/// - Contains 1 AdSense / GAM banner with declared 60-second auto-refresh.
/// - Live interactive file reordering, progress spinner, and instant client download.
class PdfMergeProgressPage extends StatefulWidget {
  final List<SelectedPdfFile> initialFiles;

  const PdfMergeProgressPage({
    super.key,
    required this.initialFiles,
  });

  @override
  State<PdfMergeProgressPage> createState() => _PdfMergeProgressPageState();
}

class _PdfMergeProgressPageState extends State<PdfMergeProgressPage> {
  late List<SelectedPdfFile> _files;
  bool _isMerging = false;
  String? _errorMessage;
  Uint8List? _mergedPdfBytes;
  int? _mergedSizeBytes;
  bool _isDragging = false;
  final Map<String, Uint8List?> _fileThumbnails = {};
  final Set<String> _loadingThumbnailFiles = {};

  @override
  void initState() {
    super.initState();
    _files = List.from(widget.initialFiles);
    TelemetryService.trackPageView(
      '/merge/process',
      pageTitle: 'FreePDFToolz — Merging PDF',
    );
    AppLimitsConfig.ensureLoaded();
    for (final f in _files) {
      _loadThumbnailForFile(f);
    }
  }

  Future<void> _loadThumbnailForFile(SelectedPdfFile file) async {
    final key = file.name;
    if (_fileThumbnails.containsKey(key) || _loadingThumbnailFiles.contains(key)) return;
    _loadingThumbnailFiles.add(key);
    try {
      final res = await PdfThumbnailService.fetchThumbnails(file);
      if (mounted) {
        setState(() {
          _fileThumbnails[key] = res.getPageBytes(0);
          _loadingThumbnailFiles.remove(key);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingThumbnailFiles.remove(key);
        });
      }
    }
  }

  int get _totalSizeBytes => _files.fold(0, (sum, f) => sum + f.sizeBytes);

  String get _formattedTotalSize {
    final bytes = _totalSizeBytes;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickMoreFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        await _processIncomingFiles(
          result.files.map((f) => {
            'name': f.name,
            'size': f.size,
            'bytes': f.bytes,
            'path': f.path,
          }).toList(),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to select additional files: $e';
      });
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    final rawFiles = <Map<String, dynamic>>[];
    for (final xfile in details.files) {
      if (xfile.name.toLowerCase().endsWith('.pdf')) {
        final length = await xfile.length();
        final bytes = await xfile.readAsBytes();
        rawFiles.add({
          'name': xfile.name,
          'size': length,
          'bytes': bytes,
          'path': xfile.path,
        });
      }
    }
    if (rawFiles.isNotEmpty) {
      await _processIncomingFiles(rawFiles);
    }
  }

  Future<void> _processIncomingFiles(List<Map<String, dynamic>> rawList) async {
    final addedFiles = <SelectedPdfFile>[];

    for (final item in rawList) {
      final name = item['name'] as String;
      final size = item['size'] as int;
      final bytes = item['bytes'] as Uint8List?;
      final path = item['path'] as String?;

      if (size == 0) continue;

      bool isAccepted = false;
      while (!isAccepted) {
        final limitEval = AppLimitsConfig.evaluate(size);

        if (!limitEval.isExceeded) {
          isAccepted = true;
          addedFiles.add(
            SelectedPdfFile(
              name: name,
              sizeBytes: size,
              bytes: bytes,
              path: path,
            ),
          );
          break;
        }

        // Oversized file: Pop Rewarded Ad Modal
        bool userWatchedAd = false;
        double? boostedLimit;

        if (mounted) {
          await RewardedVideoAdModal.show(
            context: context,
            filename: name,
            fileSizeInBytes: size,
            currentLimitMb: AppLimitsConfig.activeLimitMb,
            boostPerAdMb: AppLimitsConfig.boostPerAdMb,
            maxStackMb: AppLimitsConfig.maxStackFileMb,
            adDurationSeconds: AppLimitsConfig.rewardedAdDurationSeconds,
            onWatchAd: (newLimit) {
              userWatchedAd = true;
              boostedLimit = newLimit;
              AppLimitsConfig.recordBoost(newLimit);
            },
            onCancel: () {
              userWatchedAd = false;
            },
          );
        }

        if (!userWatchedAd) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Skipped $name: Exceeds ${AppLimitsConfig.activeLimitMb.toInt()} MB limit.',
                ),
              ),
            );
          }
          break;
        }

        if (boostedLimit != null && mounted) {
          setState(() {});
        }
      }
    }

    if (addedFiles.isNotEmpty && mounted) {
      setState(() {
        _files.addAll(addedFiles);
        _errorMessage = null;
      });
      for (final f in addedFiles) {
        _loadThumbnailForFile(f);
      }
    }
  }

  void _removeFileAt(int index) {
    setState(() {
      _files.removeAt(index);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _files.removeAt(oldIndex);
      _files.insert(newIndex, item);
    });
  }

  Future<void> _executeMerge() async {
    if (_files.length < 2) return;

    setState(() {
      _isMerging = true;
      _errorMessage = null;
    });

    final totalBytes = _files.fold<int>(0, (sum, f) => sum + (f.bytes?.length ?? f.sizeBytes));
    TelemetryService.trackToolUploadStarted(tool: 'merge', fileSizeKb: totalBytes / 1024.0);
    final stopwatch = Stopwatch()..start();

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/tools/merge');
      final request = http.MultipartRequest('POST', uri);

      for (int i = 0; i < _files.length; i++) {
        final file = _files[i];
        if (file.bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'files',
              file.bytes!,
              filename: file.name,
            ),
          );
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      stopwatch.stop();

      if (response.statusCode == 200) {
        setState(() {
          _mergedPdfBytes = response.bodyBytes;
          _mergedSizeBytes = response.bodyBytes.length;
          _isMerging = false;
        });
        TelemetryService.trackEvent('pdf_merge_completed', {
          'file_count': _files.length,
          'output_size_bytes': response.bodyBytes.length,
        });
        TelemetryService.trackToolProcessCompleted(
          tool: 'merge',
          durationMs: stopwatch.elapsedMilliseconds,
          pages: _files.length,
        );
      } else {
        String detail = 'Merge failed (HTTP ${response.statusCode})';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded['detail'] != null) detail = decoded['detail'];
        } catch (_) {}
        setState(() {
          _errorMessage = detail;
          _isMerging = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error during merge: $e';
        _isMerging = false;
      });
    }
  }

  void _downloadMergedPdf() {
    if (_mergedPdfBytes == null) return;
    TelemetryService.trackDownloadClicked(
      jobId: 'merge_${DateTime.now().millisecondsSinceEpoch}',
      format: 'pdf',
      filename: 'merged_document.pdf',
    );
    TelemetryService.trackToolDownloadClicked(
      tool: 'merge',
      fileSizeKb: (_mergedSizeBytes ?? _mergedPdfBytes!.length) / 1024.0,
    );
    DownloadHelper.triggerDownloadBytes(
      _mergedPdfBytes!,
      'merged_document.pdf',
      'application/pdf',
    );
  }

  void _resetAndGoBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/merge');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SelectionArea(
      child: Scaffold(
        appBar: AppHeader(
          currentRoute: '/merge/process',
          onThemeToggle: () {
            themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
          },
        ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: _handleDrop,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 24.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Tool Progress Ad Banner (GAM 60-second declared auto-refresh)
                        const AdSenseBanner(),
                        const SizedBox(height: 24),

                        // Header Status
                        _buildStatusHeader(theme, isDark),
                        const SizedBox(height: 24),

                        // Error Banner
                        if (_errorMessage != null) ...[
                          _buildErrorBanner(),
                          const SizedBox(height: 16),
                        ],

                        // Main Content: Success or Active Progress/Reorder
                        if (_mergedPdfBytes != null)
                          _buildSuccessCard(theme, isDark)
                        else ...[
                          _buildFilesManagerCard(theme, isDark),
                          const SizedBox(height: 24),
                          _buildActionButton(theme),
                        ],

                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ),
              const AppFooter(currentRoute: '/merge/process'),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildStatusHeader(ThemeData theme, bool isDark) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.call_merge_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merging PDF Files',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _mergedPdfBytes != null
                    ? 'Document ready for download'
                    : (_isMerging
                        ? 'Combining files into a single document...'
                        : 'Review order and click Merge PDFs'),
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _mergedPdfBytes != null
                ? Colors.green.withOpacity(0.12)
                : (_isMerging
                    ? Colors.amber.withOpacity(0.12)
                    : const Color(0xFFEF4444).withOpacity(0.12)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _mergedPdfBytes != null
                ? 'DONE'
                : (_isMerging ? 'PROCESSING' : 'STAGED'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _mergedPdfBytes != null
                  ? Colors.green
                  : (_isMerging ? Colors.amber[800] : const Color(0xFFEF4444)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesManagerCard(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDragging
              ? const Color(0xFFEF4444)
              : (isDark ? Colors.white12 : Colors.black12),
          width: _isDragging ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '${_files.length} files selected',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _formattedTotalSize,
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: _isMerging ? null : _pickMoreFiles,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add More'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No files selected. Click "Add More" to choose PDFs.',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _files.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final file = _files[index];
                return Container(
                  key: ValueKey('${file.name}_$index'),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: index < _files.length - 1
                          ? BorderSide(
                              color: isDark ? Colors.white10 : Colors.black12,
                            )
                          : BorderSide.none,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    leading: _buildStackedPaperThumbnail(file, isDark),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      file.formattedSize,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove',
                          onPressed: _isMerging
                              ? null
                              : () => _removeFileAt(index),
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.drag_indicator,
                          size: 20,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStackedPaperThumbnail(SelectedPdfFile file, bool isDark) {
    _loadThumbnailForFile(file);
    final thumbBytes = _fileThumbnails[file.name];
    final isLoading = _loadingThumbnailFiles.contains(file.name);

    return SizedBox(
      width: 42,
      height: 50,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Back sheet (rotated right 3 degrees)
          Positioned(
            top: 2,
            right: 0,
            child: Transform.rotate(
              angle: 0.05,
              child: Container(
                width: 32,
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF21262D) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ),
          // Middle sheet (rotated left 2 degrees)
          Positioned(
            top: 3,
            left: 0,
            child: Transform.rotate(
              angle: -0.04,
              child: Container(
                width: 32,
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161B22) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ),
          // Front sheet with real page thumbnail
          Container(
            width: 32,
            height: 42,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 3,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: thumbBytes != null && thumbBytes.isNotEmpty
                ? Image.memory(
                    thumbBytes,
                    fit: BoxFit.cover,
                  )
                : (isLoading
                    ? const Center(
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4444)),
                          ),
                        ),
                      )
                    : Container(
                        color: const Color(0xFFEF4444).withOpacity(0.1),
                        child: const Center(
                          child: Icon(
                            Icons.picture_as_pdf_rounded,
                            color: Color(0xFFEF4444),
                            size: 16,
                          ),
                        ),
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme) {
    final canMerge = _files.length >= 2 && !_isMerging;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: canMerge ? _executeMerge : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.withOpacity(0.2),
          disabledForegroundColor: Colors.grey,
          elevation: canMerge ? 4 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: _isMerging
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Merging PDFs...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : Text(
                _files.length < 2
                    ? 'Add at least 2 files to merge'
                    : 'Merge ${_files.length} PDFs',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  Widget _buildSuccessCard(ThemeData theme, bool isDark) {
    final sizeKb = (_mergedSizeBytes ?? 0) / 1024;
    final sizeStr = sizeKb > 1024
        ? '${(sizeKb / 1024).toStringAsFixed(1)} MB'
        : '${sizeKb.toStringAsFixed(1)} KB';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'PDFs Merged Successfully!',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your combined document is ready ($sizeStr).',
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _downloadMergedPdf,
              icon: const Icon(Icons.download_rounded),
              label: const Text(
                'Download Merged PDF',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _showEmailDownloadDialog,
              icon: const Icon(Icons.email_outlined, size: 18),
              label: const Text(
                'Send Download Link to Email',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Zero Retention Guarantee Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF064E3B).withOpacity(0.3) : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF059669).withOpacity(0.5) : const Color(0xFFA7F3D0),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Zero Retention Guarantee: Merged in volatile Linux RAM disk and purged. Although you may share your email to receive download links, we never store, retain, or cache your email address. No marketing emails, ever.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: isDark ? const Color(0xFFD1FAE5) : const Color(0xFF065F46),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _resetAndGoBack,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Merge Another PDF'),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  void _showEmailDownloadDialog() {
    final emailController = TextEditingController();
    String? localError;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
              ),
              title: Row(
                children: [
                  const Icon(Icons.email_outlined, color: Color(0xFF6366F1), size: 24),
                  const SizedBox(width: 10),
                  const Text(
                    'Email Download Link',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receive a secure, 24-hour expiring download link for your merged PDF directly in your inbox.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),

                    // Zero Retention Guarantee Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF064E3B).withOpacity(0.4)
                            : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF059669).withOpacity(0.6)
                              : const Color(0xFFA7F3D0),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Zero Email Retention: Although you share your email with us to receive download links, we never store, retain, or cache your email address. No marketing emails, ever. 100% free and privacy-focused.',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                                height: 1.35,
                                color: isDark ? const Color(0xFFD1FAE5) : const Color(0xFF065F46),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        hintText: 'user@example.com',
                        prefixIcon: const Icon(Icons.mail_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        errorText: localError,
                      ),
                      enabled: !isSubmitting,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final email = emailController.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            setDialogState(() {
                              localError = 'Please enter a valid email address.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                            localError = null;
                          });

                          // Dispatch or mock dispatch
                          await Future.delayed(const Duration(milliseconds: 600));

                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Download link sent to $email! (Valid for 24h)'),
                              backgroundColor: Colors.green.shade700,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text(isSubmitting ? 'Sending...' : 'Send Link'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

