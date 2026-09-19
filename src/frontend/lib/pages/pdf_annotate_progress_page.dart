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
  select,
  highlight,
  underline,
  note,
}

class AnnotationItem {
  final String id;
  final int pageIndex; // 0-indexed
  final AnnotationToolType tool;
  final Rect relativeRect; // Coordinates relative to page (0.0 to 1.0)
  final Color color;
  final String content;

  AnnotationItem({
    required this.id,
    required this.pageIndex,
    required this.tool,
    required this.relativeRect,
    required this.color,
    this.content = '',
  });

  AnnotationItem copyWith({
    String? id,
    int? pageIndex,
    AnnotationToolType? tool,
    Rect? relativeRect,
    Color? color,
    String? content,
  }) {
    return AnnotationItem(
      id: id ?? this.id,
      pageIndex: pageIndex ?? this.pageIndex,
      tool: tool ?? this.tool,
      relativeRect: relativeRect ?? this.relativeRect,
      color: color ?? this.color,
      content: content ?? this.content,
    );
  }

  Map<String, dynamic> toJson(double pdfWidth, double pdfHeight) {
    String typeStr = 'highlight';
    switch (tool) {
      case AnnotationToolType.highlight:
        typeStr = 'highlight';
        break;
      case AnnotationToolType.underline:
        typeStr = 'underline';
        break;
      case AnnotationToolType.note:
        typeStr = 'text';
        break;
      case AnnotationToolType.select:
        typeStr = 'highlight';
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

  // Zoom control state: 100% fits full width with 4x (16px) margins; zoomable up to 175%
  double _zoom = 1.0;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnails = false;
  bool _isUploadingThumbnails = false;
  int _thumbnailSentBytes = 0;
  int _thumbnailTotalBytes = 0;
  String? _sessionFileId;

  // Active Tool & Style
  AnnotationToolType _activeTool = AnnotationToolType.highlight;
  Color _activeColor = const Color(0xFFFEF08A); // Classic Post-it / Highlight Yellow

  // Preset Color Swatches
  final List<Color> _colorPalette = const [
    Color(0xFFFEF08A), // Classic Post-it Yellow
    Color(0xFFFDE047), // Vibrant Highlighter Yellow
    Color(0xFF86EFAC), // Soft Mint Green
    Color(0xFF7DD3FC), // Sky Blue
    Color(0xFFF472B6), // Pastel Pink
    Color(0xFFFCA5A5), // Soft Coral Red
    Color(0xFFC084FC), // Lavender Purple
  ];

  // Annotation Collections & Selection State
  final List<AnnotationItem> _annotations = [];
  String? _selectedAnnotationId;

  // Undo & Redo History Stacks
  final List<List<AnnotationItem>> _undoStack = [];
  final List<List<AnnotationItem>> _redoStack = [];

  // Active Drawing & Dragging State
  Offset? _drawStart;
  Offset? _drawCurrent;
  Offset? _moveStartGlobal;
  Rect? _moveInitialRect;

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
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
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
      dpi: 150,
      maxDimension: 2200,
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

  double _getCurrentPageWidth() {
    if (_thumbnailResult != null && _thumbnailResult!.isSuccess) {
      final pageIndex = _currentPage - 1;
      if (pageIndex < _thumbnailResult!.pages.length) {
        return _thumbnailResult!.pages[pageIndex].width;
      }
    }
    return 595.0; // Standard A4 points
  }

  double _getCurrentPageHeight() {
    if (_thumbnailResult != null && _thumbnailResult!.isSuccess) {
      final pageIndex = _currentPage - 1;
      if (pageIndex < _thumbnailResult!.pages.length) {
        return _thumbnailResult!.pages[pageIndex].height;
      }
    }
    return 842.0; // Standard A4 points
  }

  void _pushSnapshot() {
    _undoStack.add(_annotations.map((a) => a.copyWith()).toList());
    _redoStack.clear();
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(_annotations.map((a) => a.copyWith()).toList());
      _annotations.clear();
      _annotations.addAll(_undoStack.removeLast());
      _selectedAnnotationId = null;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(_annotations.map((a) => a.copyWith()).toList());
      _annotations.clear();
      _annotations.addAll(_redoStack.removeLast());
      _selectedAnnotationId = null;
    });
  }

  void _deleteSelectedAnnotation() {
    if (_selectedAnnotationId == null) return;
    _pushSnapshot();
    setState(() {
      _annotations.removeWhere((a) => a.id == _selectedAnnotationId);
      _selectedAnnotationId = null;
    });
  }

  void _updateSelectedAnnotationColor(Color newColor) {
    setState(() {
      _activeColor = newColor;
    });
    if (_selectedAnnotationId != null) {
      final idx = _annotations.indexWhere((a) => a.id == _selectedAnnotationId);
      if (idx != -1) {
        _pushSnapshot();
        setState(() {
          _annotations[idx] = _annotations[idx].copyWith(color: newColor);
        });
      }
    }
  }

  void _zoomIn() {
    setState(() {
      _zoom = (_zoom + 0.25).clamp(0.75, 1.75);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoom = (_zoom - 0.25).clamp(0.75, 1.75);
    });
  }

  void _resetZoom() {
    setState(() {
      _zoom = 1.0;
    });
  }

  Future<void> _saveAndDownload() async {
    if (_file == null) return;

    final startTime = DateTime.now();
    TelemetryService.trackToolUploadStarted(
      tool: 'annotate',
      fileSizeKb: (_file?.sizeBytes ?? 0) / 1024,
    );

    final pageWidth = _getCurrentPageWidth();
    final pageHeight = _getCurrentPageHeight();
    final pdfPayload = _annotations.map((a) => a.toJson(pageWidth, pageHeight)).toList();

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

  Future<void> _promptStickyNoteDialog(Offset relativePoint, {AnnotationItem? existing}) async {
    final textController = TextEditingController(text: existing?.content ?? '');
    final isEditing = existing != null;

    final noteText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFDE047).withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.note_alt_rounded, color: Color(0xFFD97706), size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              isEditing ? 'Edit Sticky Note' : 'Add Sticky Note',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Type your notes, comments, or review feedback:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              maxLines: 5,
              style: const TextStyle(fontSize: 14, height: 1.4),
              decoration: InputDecoration(
                hintText: 'e.g., Review this clause before sign-off...',
                filled: true,
                fillColor: const Color(0xFFFEF9C3).withOpacity(0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFFDE047)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(isEditing ? 'Save Changes' : 'Place Note'),
          ),
        ],
      ),
    );

    if (noteText != null && noteText.isNotEmpty) {
      _pushSnapshot();
      setState(() {
        if (isEditing) {
          final idx = _annotations.indexWhere((a) => a.id == existing.id);
          if (idx != -1) {
            _annotations[idx] = existing.copyWith(content: noteText);
          }
        } else {
          final noteId = 'note_${DateTime.now().microsecondsSinceEpoch}';
          // Note size: ~18% width, ~10% height relative to page
          _annotations.add(AnnotationItem(
            id: noteId,
            pageIndex: _currentPage - 1,
            tool: AnnotationToolType.note,
            relativeRect: Rect.fromLTWH(
              (relativePoint.dx - 0.09).clamp(0.01, 0.80),
              (relativePoint.dy - 0.05).clamp(0.01, 0.88),
              0.18,
              0.10,
            ),
            color: _activeColor,
            content: noteText,
          ));
          _selectedAnnotationId = noteId;
        }
      });
    }
  }

  void _showCustomColorPickerDialog() {
    final List<Color> customColors = [
      const Color(0xFFFEF08A), const Color(0xFFFDE047), const Color(0xFFFACC15), const Color(0xFFEAB308),
      const Color(0xFFBBF7D0), const Color(0xFF86EFAC), const Color(0xFF4ADE80), const Color(0xFF22C55E),
      const Color(0xFFBAE6FD), const Color(0xFF7DD3FC), const Color(0xFF38BDF8), const Color(0xFF0EA5E9),
      const Color(0xFFFBCFE8), const Color(0xFFF472B6), const Color(0xFFEC4899), const Color(0xFFDB2777),
      const Color(0xFFFECACA), const Color(0xFFFCA5A5), const Color(0xFFF87171), const Color(0xFFEF4444),
      const Color(0xFFE9D5FF), const Color(0xFFC084FC), const Color(0xFFA855F7), const Color(0xFF9333EA),
      const Color(0xFFFED7AA), const Color(0xFFFDBA74), const Color(0xFFFB923C), const Color(0xFFF97316),
      const Color(0xFFE2E8F0), const Color(0xFF94A3B8), const Color(0xFF64748B), const Color(0xFF334155),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.palette_rounded, color: Color(0xFFD97706)),
            SizedBox(width: 8),
            Text('Select Custom Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pick a color for your annotations:', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: customColors.map((c) {
                  final isCurrent = _activeColor == c;
                  return InkWell(
                    onTap: () {
                      _updateSelectedAnnotationColor(c);
                      Navigator.of(ctx).pop();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCurrent ? Colors.black : Colors.black12,
                          width: isCurrent ? 2.5 : 1,
                        ),
                        boxShadow: isCurrent
                            ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 6, spreadRadius: 1)]
                            : null,
                      ),
                      child: isCurrent
                          ? const Icon(Icons.check, size: 16, color: Colors.black87)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const AppHeader(),
            const SizedBox(height: 12),

            // Top Ad Banner (Ad #2)
            const Center(
              child: AdSenseBanner(),
            ),
            const SizedBox(height: 12),

            // Error Message
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
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

            // Main Document & Annotation Viewport
            if (_annotatedPdfBytes != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildResultCard(theme, isDark),
              )
            else if (_isLoadingThumbnails)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ToolUploadProgressIndicator(
                  sentBytes: _thumbnailSentBytes,
                  totalBytes: _thumbnailTotalBytes,
                  isUploading: _isUploadingThumbnails,
                  processingLabel: 'Rendering full-scale document pages at 100% original fidelity...',
                  accentColor: const Color(0xFFD97706),
                ),
              )
            else
              _buildFullWidthEditor(theme, isDark),

            const SizedBox(height: 48),
            const AppFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildFullWidthEditor(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Document Overview Card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildDocumentCard(theme, isDark),
        ),
        const SizedBox(height: 10),

        // Slim Adobe Reader-Style Docked Toolbar (16px horizontal margin)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildAdobeReaderToolbar(theme, isDark),
        ),
        const SizedBox(height: 12),

        // Full Width Document Canvas Viewport (4x horizontal padding = 16px margins)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildFullWidthCanvas(theme, isDark),
        ),
      ],
    );
  }

  Widget _buildDocumentCard(ThemeData theme, bool isDark) {
    final sizeKb = ((_file?.sizeBytes ?? 0) / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFD97706).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFD97706), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _file?.name ?? 'Document.pdf',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$_pageCount Pages  •  $sizeKb KB  •  Full 100% Page Width Editor',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushReplacementNamed('/annotate'),
            icon: const Icon(Icons.change_circle_outlined, size: 18),
            tooltip: 'Change Document',
          ),
        ],
      ),
    );
  }

  Widget _buildAdobeReaderToolbar(ThemeData theme, bool isDark) {
    final canUndo = _undoStack.isNotEmpty;
    final canRedo = _redoStack.isNotEmpty;
    final hasSelection = _selectedAnnotationId != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Back Button
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.arrow_back, size: 18),
              onPressed: () => Navigator.of(context).pushReplacementNamed('/annotate'),
              tooltip: 'Back to Annotate PDF',
            ),
            _buildToolbarDivider(isDark),

            // Page Navigation (Adobe Reader style on left)
            IconButton(
              key: const Key('annotate_prev_page_btn'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
              tooltip: 'Previous Page',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                'Page $_currentPage of $_pageCount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            IconButton(
              key: const Key('annotate_next_page_btn'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              onPressed: _currentPage < _pageCount ? () => setState(() => _currentPage++) : null,
              tooltip: 'Next Page',
            ),
            _buildToolbarDivider(isDark),

            // Zoom Controls (Adobe Reader style on left)
            IconButton(
              key: const Key('annotate_zoom_out_btn'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.remove_rounded, size: 18),
              onPressed: _zoom > 0.75 ? _zoomOut : null,
              tooltip: 'Zoom Out (75% min)',
            ),
            InkWell(
              key: const Key('annotate_zoom_reset_btn'),
              onTap: _resetZoom,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _zoom == 1.0 ? const Color(0xFFD97706).withOpacity(0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${(_zoom * 100).round()}%',
                  key: const Key('annotate_zoom_level_text'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _zoom == 1.0 ? const Color(0xFFD97706) : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ),
            IconButton(
              key: const Key('annotate_zoom_in_btn'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: _zoom < 1.75 ? _zoomIn : null,
              tooltip: 'Zoom In (175% max)',
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.fit_screen_rounded, size: 17),
              onPressed: _resetZoom,
              tooltip: 'Fit Width (100%)',
            ),
            _buildToolbarDivider(isDark),

            // Tool: Select / Move
            _buildToolbarToolItem(
              key: const Key('tool_select_btn'),
              tool: AnnotationToolType.select,
              icon: Icons.near_me_rounded,
              label: 'Select',
              tooltip: 'Select & Move Annotation (V)',
              isDark: isDark,
            ),
            const SizedBox(width: 3),

            // Tool: Highlight
            _buildToolbarToolItem(
              key: const Key('tool_highlight_btn'),
              tool: AnnotationToolType.highlight,
              icon: Icons.highlight_rounded,
              label: 'Highlight',
              tooltip: 'Highlight Text (H)',
              isDark: isDark,
            ),
            const SizedBox(width: 3),

            // Tool: Underline
            _buildToolbarToolItem(
              key: const Key('tool_underline_btn'),
              tool: AnnotationToolType.underline,
              icon: Icons.format_underlined_rounded,
              label: 'Underline',
              tooltip: 'Underline Text (U)',
              isDark: isDark,
            ),
            const SizedBox(width: 3),

            // Tool: Sticky Note
            _buildToolbarToolItem(
              key: const Key('tool_note_btn'),
              tool: AnnotationToolType.note,
              icon: Icons.sticky_note_2_rounded,
              label: 'Sticky Note',
              tooltip: 'Add Realistic Sticky Note (N)',
              isDark: isDark,
            ),
            _buildToolbarDivider(isDark),

            // Color Swatches (Compact)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToolbarColorSwatch(const Color(0xFFFEF08A), const Key('color_palette_yellow')),
                const SizedBox(width: 4),
                _buildToolbarColorSwatch(const Color(0xFF86EFAC), const Key('color_palette_green')),
                const SizedBox(width: 4),
                _buildToolbarColorSwatch(const Color(0xFF7DD3FC), const Key('color_palette_cyan')),
                const SizedBox(width: 4),
                _buildToolbarColorSwatch(const Color(0xFFF472B6), const Key('color_palette_pink')),
                const SizedBox(width: 4),
                // Custom Color Picker Button
                InkWell(
                  onTap: _showCustomColorPickerDialog,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade400),
                      gradient: const SweepGradient(
                        colors: [
                          Colors.red, Colors.yellow, Colors.green,
                          Colors.cyan, Colors.blue, Colors.purple, Colors.red,
                        ],
                      ),
                    ),
                    child: const Icon(Icons.colorize_rounded, size: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
            _buildToolbarDivider(isDark),

            // Undo & Redo Actions
            IconButton(
              key: const Key('annotate_undo_btn'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.undo_rounded, size: 18),
              onPressed: canUndo ? _undo : null,
              tooltip: 'Undo (Ctrl+Z)',
            ),
            IconButton(
              key: const Key('annotate_redo_btn'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.redo_rounded, size: 18),
              onPressed: canRedo ? _redo : null,
              tooltip: 'Redo (Ctrl+Y)',
            ),
            IconButton(
              key: const Key('annotate_delete_selected_btn'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              onPressed: hasSelection ? _deleteSelectedAnnotation : null,
              tooltip: 'Delete Selected Annotation',
            ),
            _buildToolbarDivider(isDark),

            // Save & Download Button
            ElevatedButton.icon(
              key: const Key('save_and_download_btn'),
              onPressed: _isProcessing ? null : _saveAndDownload,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 16),
              label: Text(
                _isProcessing ? 'Applying...' : 'Save Annotations & Download',
                style: const TextStyle(fontSize: 12.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarDivider(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      width: 1,
      height: 20,
      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
    );
  }

  Widget _buildToolbarToolItem({
    required Key key,
    required AnnotationToolType tool,
    required IconData icon,
    required String label,
    required String tooltip,
    required bool isDark,
  }) {
    final isSelected = _activeTool == tool;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: key,
        onTap: () {
          setState(() {
            _activeTool = tool;
            if (tool != AnnotationToolType.select) {
              _selectedAnnotationId = null;
            }
          });
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFD97706)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : const Color(0xFF475569)),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarColorSwatch(Color color, Key key) {
    final isCurrent = _activeColor == color;

    return InkWell(
      key: key,
      onTap: () => _updateSelectedAnnotationColor(color),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isCurrent ? Colors.black : Colors.black12,
            width: isCurrent ? 2 : 1,
          ),
          boxShadow: isCurrent
              ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 4, spreadRadius: 1)]
              : null,
        ),
        child: isCurrent
            ? const Icon(Icons.check, size: 14, color: Colors.black87)
            : null,
      ),
    );
  }

  Widget _buildFullWidthCanvas(ThemeData theme, bool isDark) {
    final pageWidth = _getCurrentPageWidth();
    final pageHeight = _getCurrentPageHeight();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final baseWidth = math.max(360.0, availableWidth);
        final aspectRatio = pageWidth / pageHeight;

        // At 100% zoom, the document spans the full available width
        final displayW = baseWidth * _zoom;
        final displayH = (baseWidth / aspectRatio) * _zoom;

        return Container(
          key: const Key('annotate_preview_canvas'),
          height: 720,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0B0F19) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: Scrollbar(
                controller: _verticalScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _verticalScrollController,
                  scrollDirection: Axis.vertical,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Container(
                      width: displayW,
                      height: displayH,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 18,
                            spreadRadius: 2,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          if (_activeTool == AnnotationToolType.note) {
                            final relPoint = Offset(
                              details.localPosition.dx / displayW,
                              details.localPosition.dy / displayH,
                            );
                            _promptStickyNoteDialog(relPoint);
                          } else if (_activeTool == AnnotationToolType.select) {
                            setState(() {
                              _selectedAnnotationId = null;
                            });
                          }
                        },
                        onPanStart: (details) {
                          if (_activeTool == AnnotationToolType.highlight ||
                              _activeTool == AnnotationToolType.underline) {
                            setState(() {
                              _drawStart = details.localPosition;
                              _drawCurrent = details.localPosition;
                            });
                          }
                        },
                        onPanUpdate: (details) {
                          if (_drawStart != null) {
                            setState(() {
                              _drawCurrent = details.localPosition;
                            });
                          }
                        },
                        onPanEnd: (details) {
                          if (_drawStart != null && _drawCurrent != null) {
                            final p0 = _drawStart!;
                            final p1 = _drawCurrent!;
                            final left = math.min(p0.dx, p1.dx) / displayW;
                            final top = math.min(p0.dy, p1.dy) / displayH;
                            final right = math.max(p0.dx, p1.dx) / displayW;
                            final bottom = math.max(p0.dy, p1.dy) / displayH;

                            final w = right - left;
                            final h = bottom - top;

                            if (w > 0.005 && h > 0.003) {
                              _pushSnapshot();
                              final newId = 'annot_${DateTime.now().microsecondsSinceEpoch}';
                              setState(() {
                                _annotations.add(AnnotationItem(
                                  id: newId,
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
                                _selectedAnnotationId = newId;
                              });
                            }
                            setState(() {
                              _drawStart = null;
                              _drawCurrent = null;
                            });
                          }
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Full Resolution 100% Page Content
                            Positioned.fill(
                              child: _buildFullPageBackground(displayW, displayH),
                            ),

                            // Existing Annotations Scaled to Current Zoom
                            ..._annotations
                                .where((a) => a.pageIndex == _currentPage - 1)
                                .map((a) => _buildRenderedAnnotation(a, displayW, displayH)),

                            // Active Drag Drawing Preview
                            if (_drawStart != null && _drawCurrent != null)
                              _buildActiveDrawPreview(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFullPageBackground(double displayW, double displayH) {
    if (_thumbnailResult != null && _thumbnailResult!.isSuccess) {
      final pageIndex = _currentPage - 1;
      if (pageIndex < _thumbnailResult!.pages.length) {
        final pageItem = _thumbnailResult!.pages[pageIndex];
        return Image.memory(
          pageItem.imageBytes,
          width: displayW,
          height: displayH,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
        );
      }
    }

    return Container(
      color: Colors.white,
      width: displayW,
      height: displayH,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'Page $_currentPage (Full 100% Page Width)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRenderedAnnotation(AnnotationItem item, double canvasW, double canvasH) {
    final isSelected = _selectedAnnotationId == item.id;

    if (item.tool == AnnotationToolType.note) {
      return _buildRealisticPostItNote(item, canvasW, canvasH, isSelected);
    }

    final rect = Rect.fromLTRB(
      item.relativeRect.left * canvasW,
      item.relativeRect.top * canvasH,
      item.relativeRect.right * canvasW,
      item.relativeRect.bottom * canvasH,
    );

    return Positioned.fromRect(
      rect: rect,
      child: MouseRegion(
        cursor: isSelected ? SystemMouseCursors.move : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _selectedAnnotationId = item.id;
              _activeColor = item.color;
            });
          },
          onPanStart: (details) {
            _pushSnapshot();
            setState(() {
              _selectedAnnotationId = item.id;
              _moveStartGlobal = details.globalPosition;
              _moveInitialRect = item.relativeRect;
            });
          },
          onPanUpdate: (details) {
            if (_moveStartGlobal != null && _moveInitialRect != null) {
              final delta = details.globalPosition - _moveStartGlobal!;
              final deltaRelX = delta.dx / canvasW;
              final deltaRelY = delta.dy / canvasH;

              final w = _moveInitialRect!.width;
              final h = _moveInitialRect!.height;
              final newLeft = (_moveInitialRect!.left + deltaRelX).clamp(0.0, 1.0 - w);
              final newTop = (_moveInitialRect!.top + deltaRelY).clamp(0.0, 1.0 - h);

              final idx = _annotations.indexWhere((a) => a.id == item.id);
              if (idx != -1) {
                setState(() {
                  _annotations[idx] = item.copyWith(
                    relativeRect: Rect.fromLTWH(newLeft, newTop, w, h),
                  );
                });
              }
            }
          },
          onPanEnd: (_) {
            setState(() {
              _moveStartGlobal = null;
              _moveInitialRect = null;
            });
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: item.tool == AnnotationToolType.highlight
                    ? Container(color: item.color.withOpacity(0.40))
                    : Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 3 * _zoom,
                          color: item.color,
                        ),
                      ),
              ),

              // Selection Border with Corner Handles & Delete Pill
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
                    ),
                  ),
                ),

              if (isSelected) ...[
                Positioned(left: -4, top: -4, child: _buildSelectionHandle()),
                Positioned(right: -4, top: -4, child: _buildSelectionHandle()),
                Positioned(left: -4, bottom: -4, child: _buildSelectionHandle()),
                Positioned(right: -4, bottom: -4, child: _buildSelectionHandle()),

                // Quick Action Delete Pill
                Positioned(
                  right: -8,
                  top: -28,
                  child: Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
                    child: InkWell(
                      onTap: _deleteSelectedAnnotation,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionHandle() {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
      ),
    );
  }

  Widget _buildRealisticPostItNote(AnnotationItem item, double canvasW, double canvasH, bool isSelected) {
    final left = item.relativeRect.left * canvasW;
    final top = item.relativeRect.top * canvasH;
    final noteW = math.max(140.0 * _zoom, 90.0);
    final noteH = math.max(105.0 * _zoom, 75.0);

    return Positioned(
      left: left,
      top: top,
      width: noteW,
      height: noteH,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _selectedAnnotationId = item.id;
              _activeColor = item.color;
            });
          },
          onDoubleTap: () => _promptStickyNoteDialog(Offset.zero, existing: item),
          onPanStart: (details) {
            _pushSnapshot();
            setState(() {
              _selectedAnnotationId = item.id;
              _moveStartGlobal = details.globalPosition;
              _moveInitialRect = item.relativeRect;
            });
          },
          onPanUpdate: (details) {
            if (_moveStartGlobal != null && _moveInitialRect != null) {
              final delta = details.globalPosition - _moveStartGlobal!;
              final deltaRelX = delta.dx / canvasW;
              final deltaRelY = delta.dy / canvasH;

              final w = _moveInitialRect!.width;
              final h = _moveInitialRect!.height;
              final newLeft = (_moveInitialRect!.left + deltaRelX).clamp(0.0, 1.0 - w);
              final newTop = (_moveInitialRect!.top + deltaRelY).clamp(0.0, 1.0 - h);

              final idx = _annotations.indexWhere((a) => a.id == item.id);
              if (idx != -1) {
                setState(() {
                  _annotations[idx] = item.copyWith(
                    relativeRect: Rect.fromLTWH(newLeft, newTop, w, h),
                  );
                });
              }
            }
          },
          onPanEnd: (_) {
            setState(() {
              _moveStartGlobal = null;
              _moveInitialRect = null;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: item.color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isSelected ? const Color(0xFF2563EB) : Colors.black12,
                width: isSelected ? 2.0 : 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 10 * _zoom,
                  spreadRadius: 1,
                  offset: Offset(3 * _zoom, 5 * _zoom),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 2 * _zoom,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Adhesive Strip
                    Container(
                      height: 18 * _zoom,
                      padding: EdgeInsets.symmetric(horizontal: 6 * _zoom),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.06),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.push_pin_rounded, size: 11 * _zoom, color: Colors.black54),
                              SizedBox(width: 4 * _zoom),
                              Text(
                                'Note',
                                style: TextStyle(
                                  fontSize: 10 * _zoom,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _promptStickyNoteDialog(Offset.zero, existing: item),
                                child: Icon(Icons.edit_rounded, size: 12 * _zoom, color: Colors.black54),
                              ),
                              SizedBox(width: 4 * _zoom),
                              InkWell(
                                onTap: () {
                                  _pushSnapshot();
                                  setState(() {
                                    _annotations.removeWhere((a) => a.id == item.id);
                                    if (_selectedAnnotationId == item.id) {
                                      _selectedAnnotationId = null;
                                    }
                                  });
                                },
                                child: Icon(Icons.close_rounded, size: 12 * _zoom, color: Colors.black54),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Post-It Note Content
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(8 * _zoom),
                        child: Text(
                          item.content.isEmpty ? 'Tap to add note text...' : item.content,
                          style: TextStyle(
                            fontSize: 11.5 * _zoom,
                            height: 1.3,
                            color: const Color(0xFF1F2937),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),

                // Folded Corner Dog-Ear
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CustomPaint(
                    size: Size(14 * _zoom, 14 * _zoom),
                    painter: DogEarPainter(noteColor: item.color, size: 14 * _zoom),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveDrawPreview() {
    final p0 = _drawStart!;
    final p1 = _drawCurrent!;
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
              ? _activeColor.withOpacity(0.4)
              : Colors.transparent,
          border: Border.all(
            color: _activeColor,
            width: _activeTool == AnnotationToolType.underline ? 2.5 : 1.5,
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
              color: Colors.green.withOpacity(0.12),
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
            'Your high-precision annotations and sticky notes have been stamped with ISO 32000 standard markup.',
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

class DogEarPainter extends CustomPainter {
  final Color noteColor;
  final double size;

  DogEarPainter({required this.noteColor, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final w = canvasSize.width;
    final h = canvasSize.height;

    // Subtle dark fold drop shadow
    final shadowPath = Path()
      ..moveTo(w - size, h)
      ..lineTo(w - size, h - size)
      ..lineTo(w, h - size)
      ..close();
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.12);
    canvas.drawPath(shadowPath, shadowPaint);

    // Folded corner triangle
    final foldPath = Path()
      ..moveTo(w - size, h)
      ..lineTo(w, h - size)
      ..lineTo(w, h)
      ..close();
    final hsl = HSLColor.fromColor(noteColor);
    final darkerFold = hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
    final foldPaint = Paint()..color = darkerFold;
    canvas.drawPath(foldPath, foldPaint);
  }

  @override
  bool shouldRepaint(covariant DogEarPainter oldDelegate) =>
      oldDelegate.noteColor != noteColor || oldDelegate.size != size;
}
