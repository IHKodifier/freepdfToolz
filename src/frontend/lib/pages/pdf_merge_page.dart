import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/adsense_banner.dart';
import '../widgets/rewarded_video_ad_modal.dart';
import '../utils/app_limits_config.dart';
import '../services/telemetry_service.dart';
import '../main.dart' show themeNotifier;

class SelectedPdfFile {
  final String name;
  final int sizeBytes;
  final Uint8List? bytes;
  final String? path;

  const SelectedPdfFile({
    required this.name,
    required this.sizeBytes,
    this.bytes,
    this.path,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Tool Landing Page for Merge PDF (/merge)
///
/// Ad Monetization Architecture:
/// - Displays Tool Landing Ad (Ad #1).
/// - Dynamic limit copy strictly sourced from canonical AppLimitsConfig. Zero hardcoded limits.
/// - Action-Driven Navigation: Dropping or selecting files immediately transitions to
///   the dedicated status/progress route (/merge/process) where Ad #2 (GAM 60s rotation) lives.
class PdfMergePage extends StatefulWidget {
  final List<SelectedPdfFile>? initialFiles;

  const PdfMergePage({super.key, this.initialFiles});

  @override
  State<PdfMergePage> createState() => _PdfMergePageState();
}

class _PdfMergePageState extends State<PdfMergePage> {
  late List<SelectedPdfFile> _files;
  bool _isDragging = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _files = widget.initialFiles != null ? List.from(widget.initialFiles!) : [];
    TelemetryService.trackPageView(
      '/merge',
      pageTitle: 'FreePDFToolz — Merge PDF',
    );
    AppLimitsConfig.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  int get _totalSizeBytes => _files.fold(0, (sum, f) => sum + f.sizeBytes);

  String get _formattedTotalSize {
    final bytes = _totalSizeBytes;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickFiles() async {
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
            'path': kIsWeb ? null : f.path,
          }).toList(),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to select files: $e';
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
          'path': kIsWeb ? null : xfile.path,
        });
      }
    }
    if (rawFiles.isNotEmpty) {
      await _processIncomingFiles(rawFiles);
    }
  }

  Future<void> _processIncomingFiles(List<Map<String, dynamic>> rawList) async {
    final validFiles = <SelectedPdfFile>[];

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
          validFiles.add(
            SelectedPdfFile(
              name: name,
              sizeBytes: size,
              bytes: bytes,
              path: path,
            ),
          );
          break;
        }

        // Oversized file: Pop Rewarded Ad Modal using canonical parameters
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

    if (validFiles.isNotEmpty && mounted) {
      // Action-driven navigation: navigate directly to dedicated status/progress route
      Navigator.pushNamed(
        context,
        '/merge/process',
        arguments: {'files': validFiles},
      );
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

  void _goToProgressPage() {
    if (_files.isNotEmpty) {
      Navigator.pushNamed(
        context,
        '/merge/process',
        arguments: {'files': _files},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SelectionArea(
      child: Scaffold(
        appBar: AppHeader(
          currentRoute: '/merge',
          onThemeToggle: () {
            themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
          },
        ),
      body: SingleChildScrollView(
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
                      // Tool Landing Ad Banner (Ad #1)
                      const AdSenseBanner(),
                      const SizedBox(height: 24),

                      // Tool Header Icon
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.call_merge_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'Merge PDF Files',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Combine multiple PDFs into a single document in your desired order.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 28),

                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Dropzone Area
                      _buildDropzone(theme, isDark),
                      const SizedBox(height: 20),

                      // Selected Files Reorderable List (if initialFiles passed)
                      if (_files.isNotEmpty) ...[
                        _buildFilesHeader(theme, isDark),
                        const SizedBox(height: 12),
                        _buildReorderableList(theme, isDark),
                        const SizedBox(height: 24),
                      ],

                      // Merge Action Button
                      _buildActionButton(theme),

                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
              const AppFooter(currentRoute: '/merge'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropzone(ThemeData theme, bool isDark) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: _handleDrop,
      child: InkWell(
        onTap: _pickFiles,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(
            color: _isDragging
                ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))
                : (isDark ? const Color(0xFF0F172A) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isDragging
                  ? const Color(0xFFEF4444)
                  : (isDark ? Colors.white12 : Colors.black12),
              width: _isDragging ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 48,
                color: _isDragging
                    ? const Color(0xFFEF4444)
                    : (isDark ? Colors.white70 : Colors.black45),
              ),
              const SizedBox(height: 12),
              Text(
                'Drop PDF files here, or click to browse',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              // Dynamic limit copy from AppLimitsConfig
              Text(
                AppLimitsConfig.dropzoneNoticeText,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Select PDF Files'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilesHeader(ThemeData theme, bool isDark) {
    return Row(
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          onPressed: _pickFiles,
          icon: const Icon(Icons.add, size: 16),
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
    );
  }

  Widget _buildReorderableList(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ReorderableListView.builder(
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
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Color(0xFFEF4444),
                    size: 20,
                  ),
                ),
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
                      tooltip: 'Remove file',
                      onPressed: () => _removeFileAt(index),
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
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme) {
    final canMerge = _files.length >= 2;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: canMerge ? _goToProgressPage : null,
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
        child: Text(
          _files.length < 2
              ? 'Merge PDFs'
              : 'Merge PDFs (${_files.length})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
