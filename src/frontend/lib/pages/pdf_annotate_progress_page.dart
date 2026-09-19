import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/download_helper.dart';
import '../services/pdf_thumbnail_service.dart';
import '../services/telemetry_service.dart';
import '../utils/app_limits_config.dart';
import '../widgets/adsense_banner.dart';
import '../widgets/app_footer.dart';
import '../widgets/app_header.dart';
import '../widgets/tool_upload_progress_indicator.dart';
import 'pdf_merge_page.dart' show SelectedPdfFile;

enum AnnotationToolType {
  highlight,
  underline,
  strikeout,
  box,
  note,
}

class AnnotationItem {
  final int pageIndex; // 0-indexed
  final AnnotationToolType tool;
  final Rect relativeRect; // Coordinates relative to canvas (0.0 to 1.0)
  final Color color;
  final String content;

  AnnotationItem({
    required this.pageIndex,
    required this.tool,
    required this.relativeRect,
    required this.color,
    this.content = '',
  });

  Map<String, dynamic> toJson(double pdfWidth, double pdfHeight) {
    String typeStr = 'highlight';
    switch (tool) {
      case AnnotationToolType.highlight:
        typeStr = 'highlight';
        break;
      case AnnotationToolType.underline:
        typeStr = 'underline';
        break;
      case AnnotationToolType.strikeout:
        typeStr = 'strikeout';
        break;
      case AnnotationToolType.box:
        typeStr = 'rect';
        break;
      case AnnotationToolType.note:
        typeStr = 'text';
        break;
    }

    final x0 = relativeRect.left * pdfWidth;
    final y0 = relativeRect.top * pdfHeight;
    final x1 = relativeRect.right * pdfWidth;
    final y1 = relativeRect.bottom * pdfHeight;

    return {
      'page': pageIndex,
      'type': typeStr,
      'rect': [x0, y0, x1, y1],
      'color': [
        color.r,
        color.g,
        color.b,
      ],
      'content': content,
    };
  }
}

class PdfAnnotateProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfAnnotateProgressPage({super.key, this.file});

  @override
  State<PdfAnnotateProgressPage> createState() => _PdfAnnotateProgressPageState();
}

class _PdfAnnotateProgressPageState extends State<PdfAnnotateProgressPage> {
  SelectedPdfFile? _file;
  int _currentPage = 1; // 1-indexed for display
  int _pageCount = 1;

  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnails = false;
  bool _isUploadingThumbnails = false;
  int _thumbnailSentBytes = 0;
  int _thumbnailTotalBytes = 0;
  String? _sessionFileId;

  // Active Tool & Style
  AnnotationToolType _activeTool = AnnotationToolType.highlight;
  Color _activeColor = const Color(0xFFFACC15); // Default Yellow

  final List<Color> _colorPalette = const [
    Color(0xFFFACC15), // Yellow
    Color(0xFF22C55E), // Green
    Color(0xFF06B6D4), // Cyan
    Color(0xFFEC4899), // Pink
    Color(0xFFEF4444), // Red
  ];

  // Annotation Collections
  final List<AnnotationItem> _annotations = [];

  // Active Drag Drawing
  Offset? _dragStart;
  Offset? _dragCurrent;

  // API Execution State
  bool _isProcessing = false;
  bool _isUploading = false;
  int _uploadSentBytes = 0;
  int _uploadTotalBytes = 0;
  String? _errorMessage;
  Uint8List? _annotatedPdfBytes;

  @override
  void initState() {
    super.initState();
    _file = widget.file;

    TelemetryService.trackPageView(
      '/annotate/process',
      pageTitle: 'FreePDFToolz — Annotate PDF Workspace',
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
    _pageCount = _detectPageCount(file.bytes);
    if (mounted) setState(() {});
    _loadThumbnails(file);
  }

  int _detectPageCount(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return 1;
    try {
      final text = String.fromCharCodes(bytes);
      final countMatches = RegExp(r'/Count\s+(\d+)').allMatches(text);
      if (countMatches.isNotEmpty) {
        int highest = 1;
        for (final m in countMatches) {
          final c = int.tryParse(m.group(1) ?? '1') ?? 1;
          if (c > highest) highest = c;
        }
        return highest;
      }
      final pageMatches = RegExp(r'/Type\s*/Page[^s]').allMatches(text);
      if (pageMatches.isNotEmpty) {
        return pageMatches.length;
      }
    } catch (_) {}
    return 1;
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
            _pageCount = totalPages;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _thumbnailResult = result;
      _isLoadingThumbnails = false;
      _isUploadingThumbnails = false;
      if (result.sessionFileId != null) {
        _sessionFileId = result.sessionFileId;
      }
      if (result.isSuccess && result.totalPages > 0) {
        _pageCount = result.totalPages;
      }
    });
  }

  Future<void> _saveAndDownload() async {
    if (_file == null) return;

    final startTime = DateTime.now();
    TelemetryService.trackToolUploadStarted(
      tool: 'annotate',
      fileSizeKb: (_file?.sizeBytes ?? 0) / 1024,
    );

    final pdfPayload = _annotations.map((a) => a.toJson(595.0, 842.0)).toList();

    final fields = <String, String>{
      if (_sessionFileId != null) 'session_file_id': _sessionFileId!,
      'annotations': jsonEncode(pdfPayload),
    };

    final List<UploadFileItem> files = [];
    if (_sessionFileId == null && _file?.bytes != null) {
      files.add(UploadFileItem(
        field: 'file',
        filename: _file!.name,
        bytes: _file!.bytes!,
      ));
    }

    final totalUploadBytes = files.fold<int>(0, (sum, f) => sum + f.bytes.length);

    setState(() {
      _isProcessing = true;
      _isUploading = true;
      _uploadSentBytes = 0;
      _uploadTotalBytes = totalUploadBytes;
      _errorMessage = null;
    });

    try {
      final uploadRes = await ApiService.uploadToolFiles(
        endpoint: '/tools/annotate',
        fields: fields,
        files: files,
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
        final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
        setState(() {
          _isProcessing = false;
          _isUploading = false;
          _annotatedPdfBytes = uploadRes.bytes;
        });
        TelemetryService.trackToolProcessCompleted(
          tool: 'annotate',
          durationMs: elapsedMs,
          pages: _pageCount,
        );
      } else {
        String detail = 'Server error (${uploadRes.statusCode})';
        try {
          detail = utf8.decode(uploadRes.bytes);
        } catch (_) {}
        setState(() {
          _isProcessing = false;
          _isUploading = false;
          _errorMessage = detail;
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _isUploading = false;
        _errorMessage = 'Failed to annotate PDF: $e';
      });
    }
  }

  Future<void> _promptStickyNoteDialog(Offset relativePoint) async {
    final textController = TextEditingController();
    final noteText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.comment_rounded, color: Color(0xFFD97706)),
            SizedBox(width: 8),
            Text('Add Sticky Note'),
          ],
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Enter your note or comment here...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
            child: const Text('Add Note', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (noteText != null && noteText.isNotEmpty) {
      setState(() {
        _annotations.add(AnnotationItem(
          pageIndex: _currentPage - 1,
          tool: AnnotationToolType.note,
          relativeRect: Rect.fromLTWH(
            (relativePoint.dx - 0.03).clamp(0.0, 0.94),
            (relativePoint.dy - 0.03).clamp(0.0, 0.94),
            0.06,
            0.06,
          ),
          color: _activeColor,
          content: noteText,
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const AppHeader(),
            const SizedBox(height: 20),

            // Top Ad Banner (Ad #2)
            const Center(
              child: AdSenseBanner(),
            ),
            const SizedBox(height: 24),

            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Bar
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).pushReplacementNamed('/annotate'),
                          tooltip: 'Back to Annotate PDF',
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Annotate PDF Workspace',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Error Message
                    if (_errorMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withAlpha(80)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _errorMessage = null),
                            ),
                          ],
                        ),
                      ),

                    // Document Overview Card
                    _buildDocumentCard(theme, isDark),
                    const SizedBox(height: 20),

                    // Thumbnail Upload Indicator
                    if (_isLoadingThumbnails) ...[
                      ToolUploadProgressIndicator(
                        sentBytes: _thumbnailSentBytes,
                        totalBytes: _thumbnailTotalBytes,
                        isUploading: _isUploadingThumbnails,
                        processingLabel: 'Generating preview thumbnails...',
                        accentColor: const Color(0xFFD97706),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (_annotatedPdfBytes != null)
                      _buildResultCard(theme, isDark)
                    else if (!_isUploadingThumbnails)
                      _buildWorkspacePanel(theme, isDark),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            const AppFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCard(ThemeData theme, bool isDark) {
    final sizeKb = ((_file?.sizeBytes ?? 0) / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFD97706).withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFD97706), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _file?.name ?? 'Document.pdf',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$_pageCount Pages  •  $sizeKb KB',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushReplacementNamed('/annotate'),
            icon: const Icon(Icons.change_circle_outlined),
            tooltip: 'Change Document',
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspacePanel(ThemeData theme, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Canvas (Left 60%)
                  Expanded(
                    flex: 60,
                    child: _buildCanvasSection(theme, isDark),
                  ),
                  const SizedBox(width: 24),
                  // Toolbar & Controls (Right 40%)
                  Expanded(
                    flex: 40,
                    child: _buildToolbarAndControls(theme, isDark),
                  ),
                ],
              )
            : Column(
                children: [
                  _buildToolbarAndControls(theme, isDark),
                  const SizedBox(height: 24),
                  _buildCanvasSection(theme, isDark),
                ],
              );
      },
    );
  }

  Widget _buildToolbarAndControls(ThemeData theme, bool isDark) {
    final currentPageAnnotations =
        _annotations.where((a) => a.pageIndex == _currentPage - 1).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Annotation Tools',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),

          // Tool Selection Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildToolButton(
                key: const Key('tool_highlight_btn'),
                tool: AnnotationToolType.highlight,
                icon: Icons.highlight_rounded,
                label: 'Highlight',
              ),
              _buildToolButton(
                key: const Key('tool_underline_btn'),
                tool: AnnotationToolType.underline,
                icon: Icons.format_underlined_rounded,
                label: 'Underline',
              ),
              _buildToolButton(
                key: const Key('tool_strikeout_btn'),
                tool: AnnotationToolType.strikeout,
                icon: Icons.strikethrough_s_rounded,
                label: 'Strikeout',
              ),
              _buildToolButton(
                key: const Key('tool_box_btn'),
                tool: AnnotationToolType.box,
                icon: Icons.crop_square_rounded,
                label: 'Box',
              ),
              _buildToolButton(
                key: const Key('tool_note_btn'),
                tool: AnnotationToolType.note,
                icon: Icons.comment_rounded,
                label: 'Sticky Note',
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Color Palette
          Text(
            'Color Palette',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildColorItem(const Color(0xFFFACC15), 'yellow', const Key('color_palette_yellow')),
              const SizedBox(width: 8),
              _buildColorItem(const Color(0xFF22C55E), 'green', const Key('color_palette_green')),
              const SizedBox(width: 8),
              _buildColorItem(const Color(0xFF06B6D4), 'cyan', const Key('color_palette_cyan')),
              const SizedBox(width: 8),
              _buildColorItem(const Color(0xFFEC4899), 'pink', const Key('color_palette_pink')),
              const SizedBox(width: 8),
              _buildColorItem(const Color(0xFFEF4444), 'red', const Key('color_palette_red')),
            ],
          ),
          const SizedBox(height: 20),

          // Annotation summary & clear
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Page markup: $currentPageAnnotations items',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: currentPageAnnotations > 0
                        ? () {
                            setState(() {
                              final lastIdx = _annotations.lastIndexWhere(
                                  (a) => a.pageIndex == _currentPage - 1);
                              if (lastIdx != -1) {
                                _annotations.removeAt(lastIdx);
                              }
                            });
                          }
                        : null,
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: const Text('Undo'),
                  ),
                  TextButton.icon(
                    onPressed: currentPageAnnotations > 0
                        ? () {
                            setState(() {
                              _annotations.removeWhere(
                                  (a) => a.pageIndex == _currentPage - 1);
                            });
                          }
                        : null,
                    icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Action Button
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _saveAndDownload,
            icon: _isProcessing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_done_rounded),
            label: Text(_isProcessing ? 'Applying Annotations...' : 'Save Annotations & Download'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required Key key,
    required AnnotationToolType tool,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _activeTool == tool;

    return OutlinedButton.icon(
      key: key,
      onPressed: () => setState(() => _activeTool = tool),
      icon: Icon(icon, size: 18, color: isSelected ? Colors.white : null),
      label: Text(
        label,
        style: TextStyle(color: isSelected ? Colors.white : null),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xFFD97706) : Colors.transparent,
        side: BorderSide(
          color: isSelected ? const Color(0xFFD97706) : Colors.grey.shade400,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildColorItem(Color color, String name, Key key) {
    final isSelected = _activeColor == color;

    return InkWell(
      key: key,
      onTap: () => setState(() => _activeColor = color),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.black : Colors.transparent,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withAlpha(128),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 18, color: Colors.black)
            : null,
      ),
    );
  }

  Widget _buildCanvasSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Page Navigation Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                key: const Key('annotate_prev_page_btn'),
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: _currentPage > 1
                    ? () => setState(() => _currentPage--)
                    : null,
                tooltip: 'Previous Page',
              ),
              Text(
                'Page $_currentPage of $_pageCount',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              IconButton(
                key: const Key('annotate_next_page_btn'),
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _currentPage < _pageCount
                    ? () => setState(() => _currentPage++)
                    : null,
                tooltip: 'Next Page',
              ),
            ],
          ),
        ),

        // Interactive Canvas Container
        Container(
          key: const Key('annotate_preview_canvas'),
          height: 520,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[950] : Colors.grey[200],
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            border: Border(
              left: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              right: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              bottom: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
          ),
          child: Center(
            child: AspectRatio(
              aspectRatio: 595.0 / 842.0,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(30),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final canvasW = constraints.maxWidth;
                    final canvasH = constraints.maxHeight;

                    return GestureDetector(
                      onTapUp: (details) {
                        if (_activeTool == AnnotationToolType.note) {
                          final relPoint = Offset(
                            details.localPosition.dx / canvasW,
                            details.localPosition.dy / canvasH,
                          );
                          _promptStickyNoteDialog(relPoint);
                        }
                      },
                      onPanStart: (details) {
                        if (_activeTool != AnnotationToolType.note) {
                          setState(() {
                            _dragStart = details.localPosition;
                            _dragCurrent = details.localPosition;
                          });
                        }
                      },
                      onPanUpdate: (details) {
                        if (_dragStart != null) {
                          setState(() {
                            _dragCurrent = details.localPosition;
                          });
                        }
                      },
                      onPanEnd: (details) {
                        if (_dragStart != null && _dragCurrent != null) {
                          final p0 = _dragStart!;
                          final p1 = _dragCurrent!;
                          final left = math.min(p0.dx, p1.dx) / canvasW;
                          final top = math.min(p0.dy, p1.dy) / canvasH;
                          final right = math.max(p0.dx, p1.dx) / canvasW;
                          final bottom = math.max(p0.dy, p1.dy) / canvasH;

                          final w = right - left;
                          final h = bottom - top;

                          // Only add if significant drag
                          if (w > 0.01 && h > 0.005) {
                            setState(() {
                              _annotations.add(AnnotationItem(
                                pageIndex: _currentPage - 1,
                                tool: _activeTool,
                                relativeRect: Rect.fromLTRB(
                                  left.clamp(0.0, 1.0),
                                  top.clamp(0.0, 1.0),
                                  right.clamp(0.0, 1.0),
                                  bottom.clamp(0.0, 1.0),
                                ),
                                color: _activeColor,
                              ));
                            });
                          }
                          setState(() {
                            _dragStart = null;
                            _dragCurrent = null;
                          });
                        }
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Thumbnail Page Background
                          Positioned.fill(
                            child: _buildThumbnailBackground(),
                          ),

                          // Existing Annotations on current page
                          ..._annotations
                              .where((a) => a.pageIndex == _currentPage - 1)
                              .map((a) => _buildRenderedAnnotation(a, canvasW, canvasH)),

                          // Active Drag Box Preview
                          if (_dragStart != null && _dragCurrent != null)
                            _buildActiveDragPreview(canvasW, canvasH),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnailBackground() {
    if (_thumbnailResult != null && _thumbnailResult!.isSuccess) {
      final pageIndex = _currentPage - 1;
      if (pageIndex < _thumbnailResult!.pages.length) {
        final pageItem = _thumbnailResult!.pages[pageIndex];
        return Image.memory(
          pageItem.imageBytes,
          fit: BoxFit.contain,
        );
      }
    }

    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'Page $_currentPage Preview',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRenderedAnnotation(AnnotationItem item, double canvasW, double canvasH) {
    final rect = Rect.fromLTRB(
      item.relativeRect.left * canvasW,
      item.relativeRect.top * canvasH,
      item.relativeRect.right * canvasW,
      item.relativeRect.bottom * canvasH,
    );

    switch (item.tool) {
      case AnnotationToolType.highlight:
        return Positioned.fromRect(
          rect: rect,
          child: Container(
            color: item.color.withAlpha(90),
          ),
        );

      case AnnotationToolType.underline:
        return Positioned.fromRect(
          rect: rect,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 3,
              color: item.color,
            ),
          ),
        );

      case AnnotationToolType.strikeout:
        return Positioned.fromRect(
          rect: rect,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              height: 2,
              color: item.color,
            ),
          ),
        );

      case AnnotationToolType.box:
        return Positioned.fromRect(
          rect: rect,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: item.color, width: 2),
            ),
          ),
        );

      case AnnotationToolType.note:
        return Positioned.fromRect(
          rect: rect,
          child: Tooltip(
            message: item.content,
            child: Container(
              decoration: BoxDecoration(
                color: item.color,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: const Icon(Icons.comment, size: 16, color: Colors.white),
            ),
          ),
        );
    }
  }

  Widget _buildActiveDragPreview(double canvasW, double canvasH) {
    final p0 = _dragStart!;
    final p1 = _dragCurrent!;
    final left = math.min(p0.dx, p1.dx);
    final top = math.min(p0.dy, p1.dy);
    final w = (p1.dx - p0.dx).abs();
    final h = (p1.dy - p0.dy).abs();

    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: Container(
        decoration: BoxDecoration(
          color: _activeTool == AnnotationToolType.highlight
              ? _activeColor.withAlpha(90)
              : Colors.transparent,
          border: Border.all(
            color: _activeColor,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            'PDF Annotated Successfully!',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Your annotations have been stamped with ISO 32000 standard markup.',
            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  TelemetryService.trackToolDownloadClicked(
                    tool: 'annotate',
                    fileSizeKb: (_annotatedPdfBytes?.length ?? 0) / 1024,
                  );
                  DownloadHelper.triggerDownloadBytes(
                    _annotatedPdfBytes!,
                    'annotated_${_file?.name ?? "document.pdf"}',
                  );
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download Annotated PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushReplacementNamed('/annotate'),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Annotate Another PDF'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Ad #3
          const Center(
            child: AdSenseBanner(),
          ),
        ],
      ),
    );
  }
}
