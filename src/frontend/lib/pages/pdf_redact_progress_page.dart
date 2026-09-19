import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/adsense_banner.dart';
import '../widgets/tool_upload_progress_indicator.dart';
import '../utils/app_limits_config.dart';
import '../services/telemetry_service.dart';
import '../services/download_helper.dart';
import '../services/api_service.dart';
import '../services/pdf_thumbnail_service.dart';
import 'pdf_merge_page.dart' show SelectedPdfFile;

/// Dedicated Status & Configuration Workspace for Redact PDF (/redact/process)
///
/// Ad Monetization Architecture:
/// - Dedicated route for Ad #2 (GAM 60s rotation).
/// - Search & Redact bar with quick sensitive pattern suggestions.
/// - Case sensitivity toggle switch.
/// - Security Guarantee Shield verifying true cryptographic glyph sanitization.
/// - Live Document Preview with animated redaction bars.
/// - In-memory client download with Ad #3.
class PdfRedactProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfRedactProgressPage({super.key, this.file});

  @override
  State<PdfRedactProgressPage> createState() => _PdfRedactProgressPageState();
}

class _PdfRedactProgressPageState extends State<PdfRedactProgressPage> {
  SelectedPdfFile? _file;
  int _detectedPages = 1;
  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnails = false;
  bool _isUploadingThumbnails = false;
  int _thumbnailSentBytes = 0;
  int _thumbnailTotalBytes = 0;
  double _previewZoom = 1.0;

  final TextEditingController _searchController = TextEditingController();
  bool _caseSensitive = false;

  bool _isProcessing = false;
  bool _isUploading = false;
  int _uploadSentBytes = 0;
  int _uploadTotalBytes = 0;
  String? _errorMessage;

  // Generated Result
  Uint8List? _resultBytes;
  String? _resultFilename;

  static const Color _redactColor = Color(0xFFE11D48);

  final List<String> _quickSuggestions = const [
    'CONFIDENTIAL',
    'SSN',
    'DO NOT DISCLOSE',
    'RESTRICTED',
    'INTERNAL ONLY',
    'Account Number',
  ];

  @override
  void initState() {
    super.initState();
    _file = widget.file;

    TelemetryService.trackPageView(
      '/redact/process',
      pageTitle: 'FreePDFToolz — Redact PDF',
    );
    AppLimitsConfig.ensureLoaded();

    if (_file != null) {
      _initDocumentState(_file!);
    }

    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initDocumentState(SelectedPdfFile file) {
    _detectedPages = _detectPageCount(file.bytes);
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

  Future<void> _applyRedaction() async {
    final query = _searchController.text.trim();
    if (_file == null || _file!.bytes == null || query.isEmpty) return;

    final sessionFileId = _thumbnailResult?.sessionFileId;
    final bool useStagedFile = sessionFileId != null && sessionFileId.isNotEmpty;
    final totalBytes = useStagedFile ? 1 : _file!.bytes!.length;

    setState(() {
      _isProcessing = true;
      _isUploading = true;
      _uploadSentBytes = 0;
      _uploadTotalBytes = totalBytes;
      _errorMessage = null;
    });

    try {
      final fields = <String, String>{
        'search_phrase': query,
        'case_sensitive': _caseSensitive.toString(),
      };
      final List<UploadFileItem> files = [];
      if (useStagedFile) {
        fields['session_file_id'] = sessionFileId;
      } else {
        files.add(
          UploadFileItem(
            field: 'file',
            filename: _file!.name,
            bytes: _file!.bytes!,
          ),
        );
      }

      final uploadRes = await ApiService.uploadToolFiles(
        endpoint: '/tools/redact',
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
        final rawStem = _file!.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        final outName = uploadRes.filename ?? '${rawStem}_redacted.pdf';

        setState(() {
          _resultBytes = uploadRes.bytes;
          _resultFilename = outName;
          _isProcessing = false;
          _isUploading = false;
        });

        TelemetryService.trackEvent('redact_completed', {
          'filename': _file!.name,
          'pages': _detectedPages,
          'case_sensitive': _caseSensitive,
        });
      } else {
        String detail = 'Redaction failed with status ${uploadRes.statusCode}';
        try {
          detail = utf8.decode(uploadRes.bytes);
        } catch (_) {}
        setState(() {
          _errorMessage = detail;
          _isProcessing = false;
          _isUploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: $e';
        _isProcessing = false;
        _isUploading = false;
      });
    }
  }

  void _resetRedact() {
    setState(() {
      _resultBytes = null;
      _resultFilename = null;
      _errorMessage = null;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      appBar: const AppHeader(currentRoute: '/redact'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1100),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  children: [
                    // Route Back / Title Row
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: 'Back to Redact Home',
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Redact PDF Workspace',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Top Workspace Ad (#2 GAM 60s)
                    const AdSenseBanner(),
                    const SizedBox(height: 24),

                    if (_file == null) ...[
                      const Center(child: Text('No PDF file loaded.')),
                    ] else if (_resultBytes != null) ...[
                      _buildResultCard(isDark),
                    ] else ...[
                      // Main Interactive Configurator
                      _buildWorkspaceLayout(isDark),
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

  Widget _buildWorkspaceLayout(bool isDark) {
    return Column(
      children: [
        if (_isLoadingThumbnails) ...[
          ToolUploadProgressIndicator(
            sentBytes: _thumbnailSentBytes,
            totalBytes: _thumbnailTotalBytes,
            isUploading: _isUploadingThumbnails,
            processingLabel: 'Generating page thumbnails...',
            accentColor: _redactColor,
          ),
          const SizedBox(height: 20),
        ],
        if (!_isUploadingThumbnails)
          LayoutBuilder(
          builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 850;

        if (isNarrow) {
          return Column(
            children: [
              _buildOverviewCard(isDark),
              const SizedBox(height: 20),
              _buildSecurityShieldCard(isDark),
              const SizedBox(height: 20),
              _buildRedactConfigCard(isDark),
              const SizedBox(height: 20),
              _buildLivePreviewCard(isDark),
              const SizedBox(height: 24),
              _buildActionButton(isDark),
            ],
          );
        }

        return Column(
          children: [
            _buildOverviewCard(isDark),
            const SizedBox(height: 24),
            _buildSecurityShieldCard(isDark),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Redaction Settings & Search
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      _buildRedactConfigCard(isDark),
                      const SizedBox(height: 24),
                      _buildActionButton(isDark),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Right Column: Simulated Live Preview
                Expanded(
                  flex: 4,
                  child: _buildLivePreviewCard(isDark),
                ),
              ],
            ),
          ],
        );
      },
    ),
  ],
);
  }

  Widget _buildOverviewCard(bool isDark) {
    final sizeKb = ((_file?.sizeBytes ?? 0) / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _redactColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, color: _redactColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _file?.name ?? 'document.pdf',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '$_detectedPages Pages',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$sizeKb KB',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
            label: const Text('Change File'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityShieldCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _redactColor.withOpacity(isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _redactColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_rounded, color: _redactColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'True Cryptographic Sanitization',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _redactColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Redacted text glyphs and raster pixel streams are permanently purged from the internal PDF binary tree. It is impossible to reveal, select, or scrape redacted content.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRedactConfigCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
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
          const Text(
            'Search & Redact Text',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the keyword, phrase, name, or number to sanitize across all pages.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),

          // Search Field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'e.g., CONFIDENTIAL, SSN, John Doe, 4000-1234...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _redactColor, width: 2),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF21262D) : const Color(0xFFF8FAFC),
            ),
          ),
          const SizedBox(height: 16),

          // Quick Suggestion Chips
          Text(
            'Quick Suggestions:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickSuggestions.map((s) {
              final isSelected = _searchController.text == s;
              return ActionChip(
                label: Text(s),
                backgroundColor: isSelected
                    ? _redactColor.withOpacity(0.15)
                    : (isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9)),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? _redactColor
                      : (isDark ? const Color(0xFFC9D1D9) : const Color(0xFF475569)),
                ),
                side: BorderSide(
                  color: isSelected
                      ? _redactColor
                      : (isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
                ),
                onPressed: () {
                  _searchController.text = s;
                },
              );
            }).toList(),
          ),

          const Divider(height: 36),

          // Case Sensitivity Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Match exact case',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _caseSensitive
                          ? "Matches exact casing only (e.g. 'SECRET' will not redact 'secret')"
                          : 'Sanitizes all occurrences regardless of uppercase or lowercase',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(
                value: _caseSensitive,
                activeColor: _redactColor,
                onChanged: (val) => setState(() => _caseSensitive = val),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreviewCard(bool isDark) {
    final query = _searchController.text.trim();
    final hasQuery = query.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(24),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Document Preview',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _redactColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    hasQuery ? 'TARGET: $query' : 'READY',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _redactColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Visual simulation of permanent black box glyph redaction.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
                      key: const Key('redact_zoom_out_btn'),
                      icon: const Icon(Icons.remove_rounded, size: 16),
                      tooltip: 'Zoom Out',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: _previewZoom > 0.8
                          ? () => setState(() => _previewZoom = (_previewZoom - 0.25).clamp(0.8, 2.5))
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        '${(_previewZoom * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('redact_zoom_in_btn'),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      tooltip: 'Zoom In',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: _previewZoom < 2.5
                          ? () => setState(() => _previewZoom = (_previewZoom + 0.25).clamp(0.8, 2.5))
                          : null,
                    ),
                    if (_previewZoom != 1.0)
                      IconButton(
                        icon: const Icon(Icons.restart_alt_rounded, size: 16),
                        tooltip: 'Reset Zoom (100%)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        onPressed: () => setState(() => _previewZoom = 1.0),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Document Canvas (Real Thumbnail Preview + Redaction Overlay)
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 320 * _previewZoom,
                height: 440 * _previewZoom,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF21262D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildRedactPageBackground(isDark, hasQuery),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRedactPageBackground(bool isDark, bool hasQuery) {
    final thumb = _thumbnailResult?.getPage(1);
    if (thumb != null) {
      return Stack(
        children: [
          Positioned.fill(
            child: Image.memory(
              thumb.imageBytes,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          if (hasQuery)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.04),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Container(
                      height: 12,
                      width: 140,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4),
                        ],
                      ),
                    ),
                    Container(
                      height: 12,
                      width: 100,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4),
                        ],
                      ),
                    ),
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    if (_isLoadingThumbnails) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return _buildFallbackSkeleton(isDark, hasQuery);
  }

  Widget _buildFallbackSkeleton(bool isDark, bool hasQuery) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Document Header Bar
          Container(
            height: 10,
            width: 70,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 14),

          // Line 1: Normal text
          _buildPreviewLine(isDark, 0.9),
          const SizedBox(height: 8),

          // Line 2: Redacted keyword!
          Row(
            children: [
              _buildPreviewLine(isDark, 0.3),
              const SizedBox(width: 8),
              Container(
                height: 8,
                width: 60,
                decoration: BoxDecoration(
                  color: hasQuery ? Colors.black : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              _buildPreviewLine(isDark, 0.2),
            ],
          ),
          const SizedBox(height: 8),

          // Line 3: Normal text
          _buildPreviewLine(isDark, 0.85),
          const SizedBox(height: 8),

          // Line 4: Normal text
          _buildPreviewLine(isDark, 0.95),
          const SizedBox(height: 8),

          // Line 5: Redacted keyword!
          Row(
            children: [
              Container(
                height: 8,
                width: 80,
                decoration: BoxDecoration(
                  color: hasQuery ? Colors.black : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              _buildPreviewLine(isDark, 0.4),
            ],
          ),
          const SizedBox(height: 8),

          // Line 6 & 7: Normal text
          _buildPreviewLine(isDark, 0.75),
          const SizedBox(height: 8),
          _buildPreviewLine(isDark, 0.88),
          const SizedBox(height: 8),

          // Line 8: Redacted keyword!
          Row(
            children: [
              _buildPreviewLine(isDark, 0.45),
              const SizedBox(width: 8),
              Container(
                height: 8,
                width: 50,
                decoration: BoxDecoration(
                  color: hasQuery ? Colors.black : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Line 9: Normal text
          _buildPreviewLine(isDark, 0.6),
        ],
      ),
    );
  }

  Widget _buildPreviewLine(bool isDark, double widthFraction) {
    return Container(
      height: 6,
      width: 200 * widthFraction,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildActionButton(bool isDark) {
    final canApply = _searchController.text.trim().isNotEmpty && !_isProcessing;

    return Column(
      children: [
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (_isProcessing) ...[
          ToolUploadProgressIndicator(
            isUploading: _isUploading,
            sentBytes: _uploadSentBytes,
            totalBytes: _uploadTotalBytes,
            processingLabel: 'Sanitizing document streams in RAM disk...',
          ),
          const SizedBox(height: 16),
        ],

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: canApply ? _applyRedaction : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _redactColor,
              disabledBackgroundColor: _redactColor.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isProcessing
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isUploading ? 'Uploading Document...' : 'Sanitizing Document Streams...',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_rounded, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        'Sanitize & Redact PDF',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(bool isDark) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _redactColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 56,
                  color: _redactColor,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'PDF Redacted Successfully!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'Target glyphs and pixel streams have been cryptographically sanitized.',
                style: TextStyle(
                  color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.description_outlined, size: 18, color: _redactColor),
                    const SizedBox(width: 8),
                    Text(
                      _resultFilename ?? 'document_redacted.pdf',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_resultBytes != null && _resultFilename != null) {
                        DownloadHelper.triggerDownloadBytes(_resultBytes!, _resultFilename!);
                      }
                    },
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                    label: const Text(
                      'Download Redacted PDF',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _redactColor,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: _resetRedact,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Redact Another'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        // Ad #3 on download result page
        const AdSenseBanner(),
      ],
    );
  }
}
