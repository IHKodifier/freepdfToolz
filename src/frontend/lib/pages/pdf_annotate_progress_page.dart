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
  final Offset? anchorPoint; // Callout anchor point relative to page (0.0 to 1.0) for sticky note
  final Color color;
  final String content;
  final double strokeThickness; // For underline stroke thickness (points)

  AnnotationItem({
    required this.id,
    required this.pageIndex,
    required this.tool,
    required this.relativeRect,
    this.anchorPoint,
    required this.color,
    this.content = '',
    this.strokeThickness = 2.5,
  });

  AnnotationItem copyWith({
    String? id,
    int? pageIndex,
    AnnotationToolType? tool,
    Rect? relativeRect,
    Offset? anchorPoint,
    Color? color,
    String? content,
    double? strokeThickness,
  }) {
    return AnnotationItem(
      id: id ?? this.id,
      pageIndex: pageIndex ?? this.pageIndex,
      tool: tool ?? this.tool,
      relativeRect: relativeRect ?? this.relativeRect,
      anchorPoint: anchorPoint ?? this.anchorPoint,
      color: color ?? this.color,
      content: content ?? this.content,
      strokeThickness: strokeThickness ?? this.strokeThickness,
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

    final map = <String, dynamic>{
      'page': pageIndex,
      'type': typeStr,
      'rect': [x0, y0, x1, y1],
      'color': [
        color.r,
        color.g,
        color.b,
      ],
      'content': content,
      'stroke_thickness': strokeThickness,
    };

    if (anchorPoint != null) {
      final ax = anchorPoint!.dx * pdfWidth;
      final ay = anchorPoint!.dy * pdfHeight;
      map['anchor'] = [ax, ay];
      map['point'] = [ax, ay];
    }

    return map;
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

  // Active Tool, Color & Stroke Style
  AnnotationToolType _activeTool = AnnotationToolType.highlight;
  Color _activeColor = const Color(0xFFFEF08A); // Classic Post-it / Highlight Yellow
  double _activeStrokeWidth = 2.5; // Stroke thickness for underline

  // Preset Color Swatches
  final List<Color> _colorPalette = const [
    Color(0xFFFEF08A), // Classic Post-it Yellow
    Color(0xFF86EFAC), // Soft Mint Green
    Color(0xFF7DD3FC), // Sky Blue
    Color(0xFFF472B6), // Pastel Pink
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
  Offset? _anchorMoveStartGlobal;
  Offset? _anchorInitialOffset;

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
    _deleteAnnotation(_selectedAnnotationId!);
  }

  void _deleteAnnotation(String id) {
    _pushSnapshot();
    setState(() {
      _annotations.removeWhere((a) => a.id == id);
      if (_selectedAnnotationId == id) {
        _selectedAnnotationId = null;
      }
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

  void _updateStrokeWidth(double width) {
    setState(() {
      _activeStrokeWidth = width;
    });
    if (_selectedAnnotationId != null) {
      final idx = _annotations.indexWhere((a) => a.id == _selectedAnnotationId);
      if (idx != -1 && _annotations[idx].tool == AnnotationToolType.underline) {
        _pushSnapshot();
        setState(() {
          _annotations[idx] = _annotations[idx].copyWith(strokeThickness: width);
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

  Future<void> _promptStickyNoteDialog(Offset relativeAnchorPoint, {AnnotationItem? existing}) async {
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
              'Anchored to text. Enter your notes or review feedback:',
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
          // Place the note card slightly offset to avoid obscuring the anchored text
          final noteRelX = (relativeAnchorPoint.dx + 0.05).clamp(0.01, 0.80);
          final noteRelY = (relativeAnchorPoint.dy - 0.08).clamp(0.01, 0.88);

          _annotations.add(AnnotationItem(
            id: noteId,
            pageIndex: _currentPage - 1,
            tool: AnnotationToolType.note,
            anchorPoint: relativeAnchorPoint,
            relativeRect: Rect.fromLTWH(noteRelX, noteRelY, 0.18, 0.10),
            color: _activeColor,
            content: noteText,
          ));
          _selectedAnnotationId = noteId;
        }
      });
    }
  }

  void _showFreeColorPickerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => FreeColorPickerDialog(
        initialColor: _activeColor,
        onColorSelected: (c) {
          _updateSelectedAnnotationColor(c);
        },
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

            // Underline Thickness Quick Toggles
            if (_activeTool == AnnotationToolType.underline) ...[
              _buildStrokeWidthPill(1.5, 'Thin', isDark),
              _buildStrokeWidthPill(2.5, 'Med', isDark),
              _buildStrokeWidthPill(4.0, 'Thick', isDark),
              const SizedBox(width: 3),
            ],

            // Tool: Sticky Note
            _buildToolbarToolItem(
              key: const Key('tool_note_btn'),
              tool: AnnotationToolType.note,
              icon: Icons.sticky_note_2_rounded,
              label: 'Sticky Note',
              tooltip: 'Add Anchored Callout Sticky Note (N)',
              isDark: isDark,
            ),
            _buildToolbarDivider(isDark),

            // Color Swatches & Free Color Picker
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
                const SizedBox(width: 5),
                // Continuous Free Color Picker Button
                Tooltip(
                  message: 'Free Color Picker (Full Spectrum)',
                  child: InkWell(
                    onTap: _showFreeColorPickerDialog,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade400, width: 1.2),
                        gradient: const SweepGradient(
                          colors: [
                            Colors.red, Colors.amber, Colors.green,
                            Colors.cyan, Colors.blue, Colors.purple, Colors.red,
                          ],
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
                        ],
                      ),
                      child: const Icon(Icons.colorize_rounded, size: 12, color: Colors.white),
                    ),
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

  Widget _buildStrokeWidthPill(double width, String label, bool isDark) {
    final isSelected = (_activeStrokeWidth - width).abs() < 0.1;

    return InkWell(
      onTap: () => _updateStrokeWidth(width),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD97706).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? const Color(0xFFD97706) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFFD97706) : (isDark ? Colors.white70 : Colors.black87),
          ),
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 20,
        height: 20,
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
            ? const Icon(Icons.check, size: 12, color: Colors.black87)
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

                            if (_activeTool == AnnotationToolType.underline) {
                              // Underline: strictly horizontal span + stroke thickness
                              final left = math.min(p0.dx, p1.dx) / displayW;
                              final right = math.max(p0.dx, p1.dx) / displayW;
                              final w = right - left;
                              final y = p0.dy / displayH;

                              if (w > 0.005) {
                                _pushSnapshot();
                                final newId = 'annot_${DateTime.now().microsecondsSinceEpoch}';
                                setState(() {
                                  _annotations.add(AnnotationItem(
                                    id: newId,
                                    pageIndex: _currentPage - 1,
                                    tool: AnnotationToolType.underline,
                                    relativeRect: Rect.fromLTWH(
                                      left.clamp(0.0, 1.0),
                                      y.clamp(0.0, 1.0),
                                      w.clamp(0.001, 1.0),
                                      _activeStrokeWidth / displayH,
                                    ),
                                    color: _activeColor,
                                    strokeThickness: _activeStrokeWidth,
                                  ));
                                  _selectedAnnotationId = newId;
                                });
                              }
                            } else {
                              // Highlight: 2D text bounding area
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
                                    tool: AnnotationToolType.highlight,
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

                            // Callout Connector Leader Lines (under the notes)
                            ..._annotations
                                .where((a) => a.pageIndex == _currentPage - 1 && a.tool == AnnotationToolType.note && a.anchorPoint != null)
                                .map((a) => Positioned.fill(
                                      child: CustomPaint(
                                        painter: CalloutLeaderPainter(
                                          anchorPoint: Offset(a.anchorPoint!.dx * displayW, a.anchorPoint!.dy * displayH),
                                          noteRect: Rect.fromLTWH(
                                            a.relativeRect.left * displayW,
                                            a.relativeRect.top * displayH,
                                            math.max(140.0 * _zoom, 90.0),
                                            math.max(105.0 * _zoom, 75.0),
                                          ),
                                          color: a.color,
                                        ),
                                      ),
                                    )),

                            // Draggable Anchor Points for Selected Notes
                            ..._annotations
                                .where((a) => a.pageIndex == _currentPage - 1 && a.tool == AnnotationToolType.note && a.anchorPoint != null && a.id == _selectedAnnotationId)
                                .map((a) => _buildDraggableAnchorPoint(a, displayW, displayH)),

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

  Widget _buildDraggableAnchorPoint(AnnotationItem item, double canvasW, double canvasH) {
    final anchor = item.anchorPoint!;
    final px = anchor.dx * canvasW;
    final py = anchor.dy * canvasH;

    return Positioned(
      left: px - 12,
      top: py - 12,
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            _pushSnapshot();
            _anchorMoveStartGlobal = details.globalPosition;
            _anchorInitialOffset = item.anchorPoint;
          },
          onPanUpdate: (details) {
            if (_anchorMoveStartGlobal != null && _anchorInitialOffset != null) {
              final delta = details.globalPosition - _anchorMoveStartGlobal!;
              final newDx = (_anchorInitialOffset!.dx + (delta.dx / canvasW)).clamp(0.01, 0.99);
              final newDy = (_anchorInitialOffset!.dy + (delta.dy / canvasH)).clamp(0.01, 0.99);

              final idx = _annotations.indexWhere((a) => a.id == item.id);
              if (idx != -1) {
                setState(() {
                  _annotations[idx] = item.copyWith(anchorPoint: Offset(newDx, newDy));
                });
              }
            }
          },
          onPanEnd: (_) {
            _anchorMoveStartGlobal = null;
            _anchorInitialOffset = null;
          },
          child: Tooltip(
            message: 'Drag to re-anchor callout to text',
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
              ),
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2563EB),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRenderedAnnotation(AnnotationItem item, double canvasW, double canvasH) {
    final isSelected = _selectedAnnotationId == item.id;

    if (item.tool == AnnotationToolType.note) {
      return _buildRealisticPostItNote(item, canvasW, canvasH, isSelected);
    }

    if (item.tool == AnnotationToolType.underline) {
      return _buildUnderlineAnnotation(item, canvasW, canvasH, isSelected);
    }

    // Highlight annotation
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
                child: Container(color: item.color.withOpacity(0.40)),
              ),

              // Selection Border with Corner Handles
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

                // Working Top-Right Red Cross Delete Button
                Positioned(
                  right: -8,
                  top: -8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _deleteAnnotation(item.id),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Center(
                        child: Icon(Icons.close_rounded, size: 11, color: Colors.white),
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

  Widget _buildUnderlineAnnotation(AnnotationItem item, double canvasW, double canvasH, bool isSelected) {
    final left = item.relativeRect.left * canvasW;
    final top = item.relativeRect.top * canvasH;
    final width = item.relativeRect.width * canvasW;
    final strokeH = math.max(1.5, item.strokeThickness * _zoom);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: math.max(strokeH, 16.0), // Hit area for easy interaction
      child: MouseRegion(
        cursor: isSelected ? SystemMouseCursors.move : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _selectedAnnotationId = item.id;
              _activeColor = item.color;
              _activeStrokeWidth = item.strokeThickness;
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
            alignment: Alignment.centerLeft,
            children: [
              // Underline stroke: strictly width + stroke thickness
              Container(
                width: width,
                height: strokeH,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(strokeH / 2),
                ),
              ),

              // Selection Highlight
              if (isSelected)
                Positioned(
                  left: -2,
                  top: 0,
                  right: -2,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

              // Top-Right Red Cross Delete Action
              if (isSelected)
                Positioned(
                  right: -8,
                  top: -8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _deleteAnnotation(item.id),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Center(
                        child: Icon(Icons.close_rounded, size: 11, color: Colors.white),
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Card Body & Pan Drag Handler
          MouseRegion(
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

          // Working Top-Right Red Cross Delete Action
          Positioned(
            right: -6,
            top: -6,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _deleteAnnotation(item.id),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.close_rounded, size: 12, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDrawPreview() {
    final p0 = _drawStart!;
    final p1 = _drawCurrent!;

    if (_activeTool == AnnotationToolType.underline) {
      // Underline preview: strictly width + stroke thickness
      final left = math.min(p0.dx, p1.dx);
      final width = (p1.dx - p0.dx).abs();
      final strokeH = math.max(1.5, _activeStrokeWidth * _zoom);

      return Positioned(
        left: left,
        top: p0.dy,
        width: width,
        height: strokeH,
        child: Container(
          decoration: BoxDecoration(
            color: _activeColor,
            borderRadius: BorderRadius.circular(strokeH / 2),
            boxShadow: [
              BoxShadow(color: _activeColor.withOpacity(0.5), blurRadius: 4),
            ],
          ),
        ),
      );
    }

    // Highlight preview
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
          color: _activeColor.withOpacity(0.4),
          border: Border.all(
            color: _activeColor,
            width: 1.5,
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
            'Your high-precision annotations and anchored callouts have been stamped with ISO 32000 standard markup.',
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

class CalloutLeaderPainter extends CustomPainter {
  final Offset anchorPoint; // In canvas coordinates
  final Rect noteRect; // In canvas coordinates
  final Color color;

  CalloutLeaderPainter({
    required this.anchorPoint,
    required this.noteRect,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Anchor Pin Dot at anchorPoint on the text
    final haloPaint = Paint()
      ..color = color.withOpacity(0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(anchorPoint, 7, haloPaint);

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(anchorPoint, 3.5, dotPaint);

    final dotBorderPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(anchorPoint, 3.5, dotBorderPaint);

    // 2. Find closest attachment point on note border
    double targetX = anchorPoint.dx.clamp(noteRect.left, noteRect.right);
    double targetY = anchorPoint.dy.clamp(noteRect.top, noteRect.bottom);

    if (anchorPoint.dx < noteRect.left) {
      targetX = noteRect.left;
      targetY = noteRect.top + noteRect.height * 0.35;
    } else if (anchorPoint.dx > noteRect.right) {
      targetX = noteRect.right;
      targetY = noteRect.top + noteRect.height * 0.35;
    } else if (anchorPoint.dy < noteRect.top) {
      targetY = noteRect.top;
    } else {
      targetY = noteRect.bottom;
    }

    final targetPoint = Offset(targetX, targetY);

    // 3. Draw smooth callout leader curve
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.12)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final linePaint = Paint()
      ..color = color.withOpacity(0.95)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final midX = (anchorPoint.dx + targetPoint.dx) / 2;
    final control = Offset(midX, anchorPoint.dy);

    final path = Path()
      ..moveTo(anchorPoint.dx, anchorPoint.dy)
      ..quadraticBezierTo(control.dx, control.dy, targetPoint.dx, targetPoint.dy);

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CalloutLeaderPainter oldDelegate) =>
      oldDelegate.anchorPoint != anchorPoint ||
      oldDelegate.noteRect != noteRect ||
      oldDelegate.color != color;
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

/// Continuous Free Color Picker across 16-million spectrum
class FreeColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorSelected;

  const FreeColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
  });

  @override
  State<FreeColorPickerDialog> createState() => _FreeColorPickerDialogState();
}

class _FreeColorPickerDialogState extends State<FreeColorPickerDialog> {
  late HSVColor _hsvColor;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _toHex(_hsvColor.toColor()));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _toHex(Color c) {
    return '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  void _onHexChanged(String val) {
    final clean = val.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final parsed = int.tryParse('FF$clean', radix: 16);
      if (parsed != null) {
        setState(() {
          _hsvColor = HSVColor.fromColor(Color(parsed));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _hsvColor.toColor();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.palette_rounded, color: Color(0xFFD97706)),
          SizedBox(width: 8),
          Text('Free Color Picker', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 2D Saturation-Value Continuous Field
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 160,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boxW = constraints.maxWidth;
                    final boxH = constraints.maxHeight;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (details) => _updateSV(details.localPosition, boxW, boxH),
                      onPanUpdate: (details) => _updateSV(details.localPosition, boxW, boxH),
                      child: Stack(
                        children: [
                          // Base Hue
                          Container(
                            color: HSVColor.fromAHSV(1.0, _hsvColor.hue, 1.0, 1.0).toColor(),
                          ),
                          // Horizontal White Gradient
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.white, Colors.transparent],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                          ),
                          // Vertical Black Gradient
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          // Crosshair Indicator
                          Positioned(
                            left: (_hsvColor.saturation * boxW - 8).clamp(0.0, boxW - 16),
                            top: ((1.0 - _hsvColor.value) * boxH - 8).clamp(0.0, boxH - 16),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black45, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Continuous Rainbow Hue Bar
            SizedBox(
              height: 24,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barW = constraints.maxWidth;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (details) => _updateHue(details.localPosition.dx, barW),
                    onPanUpdate: (details) => _updateHue(details.localPosition.dx, barW),
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
                                Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
                              ],
                            ),
                          ),
                        ),
                        // Hue Slider Knob
                        Positioned(
                          left: ((_hsvColor.hue / 360.0) * barW - 10).clamp(0.0, barW - 20),
                          top: 2,
                          bottom: 2,
                          child: Container(
                            width: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black45, width: 1.5),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Live Preview & Hex Input
            Row(
              children: [
                // Color Preview Box
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: currentColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black26),
                    boxShadow: [
                      BoxShadow(color: currentColor.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    onChanged: _onHexChanged,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Hex Color',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onColorSelected(currentColor);
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD97706),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Apply Color'),
        ),
      ],
    );
  }

  void _updateSV(Offset local, double w, double h) {
    final sat = (local.dx / w).clamp(0.0, 1.0);
    final val = (1.0 - (local.dy / h)).clamp(0.0, 1.0);
    setState(() {
      _hsvColor = _hsvColor.withSaturation(sat).withValue(val);
      _hexController.text = _toHex(_hsvColor.toColor());
    });
  }

  void _updateHue(double dx, double w) {
    final hue = ((dx / w).clamp(0.0, 1.0) * 360.0).clamp(0.0, 360.0);
    setState(() {
      _hsvColor = _hsvColor.withHue(hue);
      _hexController.text = _toHex(_hsvColor.toColor());
    });
  }
}
