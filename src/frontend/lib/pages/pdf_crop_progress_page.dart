import 'dart:convert';
import 'dart:math' as math;
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

/// Dedicated Status & Configuration Workspace for Crop PDF (/crop/process)
///
/// Ad Monetization Architecture:
/// - Dedicated route for Ad #2 (GAM 60s rotation).
/// - Dynamic margin preset chips ("Zero Margins", "Auto Trim 10%", "Standard 0.5in (36pt)", "Wide 1.0in (72pt)").
/// - Real-time margin sliders (Top, Bottom, Left, Right) in points.
/// - Scope toggle ("Apply to all pages" vs individual page selector).
/// - Live Document Preview Box with dynamic visual crop overlay rectangle.
/// - In-memory client download for instant output retrieval with Ad #3.
class PdfCropProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfCropProgressPage({super.key, this.file});

  @override
  State<PdfCropProgressPage> createState() => _PdfCropProgressPageState();
}

class _PdfCropProgressPageState extends State<PdfCropProgressPage> {
  SelectedPdfFile? _file;
  int _detectedPages = 1;
  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnails = false;
  bool _isUploadingThumbnails = false;
  int _thumbnailSentBytes = 0;
  int _thumbnailTotalBytes = 0;

  // Margin Configuration (in points)
  double _topMargin = 0.0;
  double _bottomMargin = 0.0;
  double _leftMargin = 0.0;
  double _rightMargin = 0.0;

  // Scope Configuration
  bool _applyToAll = true;
  int _targetPage = 1; // 1-based for UI display

  bool _isProcessing = false;
  bool _isUploading = false;
  int _uploadSentBytes = 0;
  int _uploadTotalBytes = 0;
  String? _errorMessage;

  // Generated Result
  Uint8List? _resultBytes;
  String? _resultFilename;

  @override
  void initState() {
    super.initState();
    _file = widget.file;

    TelemetryService.trackPageView(
      '/crop/process',
      pageTitle: 'FreePDFToolz — Crop PDF',
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

  void _setPreset(double left, double top, double right, double bottom) {
    setState(() {
      _leftMargin = left;
      _topMargin = top;
      _rightMargin = right;
      _bottomMargin = bottom;
    });
  }

  Future<void> _applyCrop() async {
    if (_file == null || _file!.bytes == null) return;

    final totalBytes = _file!.bytes!.length;
    setState(() {
      _isProcessing = true;
      _isUploading = true;
      _uploadSentBytes = 0;
      _uploadTotalBytes = totalBytes;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.uploadToolFiles(
        endpoint: '/tools/crop',
        files: [
          UploadFileItem(
            fieldName: 'file',
            filename: _file!.name,
            bytes: _file!.bytes!,
          ),
        ],
        fields: {
          'left': _leftMargin.toString(),
          'top': _topMargin.toString(),
          'right': _rightMargin.toString(),
          'bottom': _bottomMargin.toString(),
          'apply_to_all': _applyToAll.toString(),
          'target_page': (_targetPage - 1).toString(),
        },
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
        final rawStem = _file!.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        final outName = '${rawStem}_cropped.pdf';

        setState(() {
          _resultBytes = response.bodyBytes;
          _resultFilename = outName;
          _isProcessing = false;
          _isUploading = false;
        });

        TelemetryService.trackEvent('crop_completed', {
          'filename': _file!.name,
          'pages': _detectedPages,
          'apply_to_all': _applyToAll,
        });
      } else {
        String detail = 'Cropping failed with status ${response.statusCode}';
        try {
          final decoded = jsonDecode(response.bodyString);
          if (decoded['detail'] != null) detail = decoded['detail'];
        } catch (_) {
          if (response.bodyString.isNotEmpty) detail = response.bodyString;
        }
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

  void _resetCrop() {
    setState(() {
      _resultBytes = null;
      _resultFilename = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      appBar: const AppHeader(currentRoute: '/crop'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1100),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back navigation link
                    InkWell(
                      onTap: () => Navigator.pushReplacementNamed(context, '/crop'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                              color: isDark ? const Color(0xFF58A6FF) : const Color(0xFF0284C7),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Choose another file',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF58A6FF) : const Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Top Ad #2: Workspace GAM Ad with 60s auto-refresh
                    const AdSenseBanner(),
                    const SizedBox(height: 24),

                    // Error Banner if any
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.red),
                              onPressed: () => setState(() => _errorMessage = null),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    if (_file == null)
                      _buildNoFileSelected(context, isDark)
                    else if (_resultBytes != null)
                      _buildResultCard(context, isDark)
                    else
                      _buildWorkspaceLayout(context, isDark),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            const AppFooter(currentRoute: '/crop'),
          ],
        ),
      ),
    );
  }

  Widget _buildNoFileSelected(BuildContext context, bool isDark) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
        ),
        child: Column(
          children: [
            const Icon(Icons.find_in_page_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No PDF file selected for cropping.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/crop'),
              child: const Text('Go to Crop Page'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceLayout(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Document Overview Card
        _buildDocumentHeader(context, isDark),
        const SizedBox(height: 24),

        if (_isLoadingThumbnails) ...[
          ToolUploadProgressIndicator(
            sentBytes: _thumbnailSentBytes,
            totalBytes: _thumbnailTotalBytes,
            isUploading: _isUploadingThumbnails,
            processingLabel: 'Generating visual page previews in Linux tmpfs RAM disk...',
            accentColor: const Color(0xFF0284C7),
          ),
          const SizedBox(height: 20),
        ],

        // 2-Column Responsive Workspace: Controls (Left) & Live Preview (Right)
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 768;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: _buildControlsCard(context, isDark),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 5,
                    child: _buildLivePreviewCard(context, isDark),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  _buildControlsCard(context, isDark),
                  const SizedBox(height: 24),
                  _buildLivePreviewCard(context, isDark),
                ],
              );
            }
          },
        ),

        const SizedBox(height: 32),

        if (_isProcessing) ...[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: ToolUploadProgressIndicator(
                sentBytes: _uploadSentBytes,
                totalBytes: _uploadTotalBytes,
                isUploading: _isUploading,
                processingLabel: 'Cropping PDF Document...',
                accentColor: const Color(0xFF0284C7),
              ),
            ),
          ),
        ],

        // Primary Action: Crop Button
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _applyCrop,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.crop_rounded, color: Colors.white),
              label: Text(
                _isProcessing
                    ? (_isUploading
                        ? 'Uploading PDF (${(_uploadTotalBytes > 0 ? (_uploadSentBytes / _uploadTotalBytes * 100).toInt() : 0)}%)...'
                        : 'Cropping PDF...')
                    : 'Crop PDF',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ),
      ),
      ],
    );
  }

  Widget _buildDocumentHeader(BuildContext context, bool isDark) {
    final sizeKb = (_file!.sizeBytes / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF0284C7), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _file!.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '$_detectedPages ${_detectedPages == 1 ? 'Page' : 'Pages'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '•',
                      style: TextStyle(color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$sizeKb KB',
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
        ],
      ),
    );
  }

  Widget _buildControlsCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Crop Margins',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Trim boundaries by points (1 inch = 72 pt). Live preview updates dynamically.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),

          // Preset Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetChip('Zero Margins', 0, 0, 0, 0, isDark),
              _buildPresetChip('Auto Trim 10%', 18, 18, 18, 18, isDark),
              _buildPresetChip('Standard 0.5in (36pt)', 36, 36, 36, 36, isDark),
              _buildPresetChip('Wide 1.0in (72pt)', 72, 72, 72, 72, isDark),
            ],
          ),
          const SizedBox(height: 24),

          // Margin Sliders
          _buildMarginSlider(
            label: 'Top Margin',
            value: _topMargin,
            onChanged: (v) => setState(() => _topMargin = v),
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildMarginSlider(
            label: 'Bottom Margin',
            value: _bottomMargin,
            onChanged: (v) => setState(() => _bottomMargin = v),
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildMarginSlider(
            label: 'Left Margin',
            value: _leftMargin,
            onChanged: (v) => setState(() => _leftMargin = v),
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildMarginSlider(
            label: 'Right Margin',
            value: _rightMargin,
            onChanged: (v) => setState(() => _rightMargin = v),
            isDark: isDark,
          ),

          const Divider(height: 36),

          // Scope Configuration
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Apply to all pages',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _applyToAll
                          ? 'Cropping will be applied uniformly across all $_detectedPages pages'
                          : 'Cropping will only apply to page $_targetPage',
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
                value: _applyToAll,
                activeColor: const Color(0xFF0284C7),
                onChanged: (val) => setState(() => _applyToAll = val),
              ),
            ],
          ),

          // Target Page Selector when not applying to all pages
          if (!_applyToAll) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF21262D) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Text(
                    'Target Page:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: _targetPage > 1 ? () => setState(() => _targetPage--) : null,
                  ),
                  Text(
                    'Page $_targetPage of $_detectedPages',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: _targetPage < _detectedPages ? () => setState(() => _targetPage++) : null,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, double l, double t, double r, double b, bool isDark) {
    final isSelected = (_leftMargin == l && _topMargin == t && _rightMargin == r && _bottomMargin == b);

    return InkWell(
      onTap: () => _setPreset(l, t, r, b),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0284C7)
              : (isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF0284C7) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFFC9D1D9) : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Widget _buildMarginSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${value.toInt()} pt',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0284C7)),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF0284C7),
            thumbColor: const Color(0xFF0284C7),
            inactiveTrackColor: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
            trackHeight: 4,
          ),
          child: Slider(
            value: value,
            min: 0.0,
            max: 144.0,
            divisions: 144,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildLivePreviewCard(BuildContext context, bool isDark) {
    // Simulated A4 page dimensions: 595 x 842 pt
    const baseW = 595.0;
    const baseH = 842.0;

    final remainingW = math.max(10.0, baseW - _leftMargin - _rightMargin);
    final remainingH = math.max(10.0, baseH - _topMargin - _bottomMargin);

    // Calculate proportions for preview overlay box
    final leftFrac = (_leftMargin / baseW).clamp(0.0, 0.45);
    final topFrac = (_topMargin / baseH).clamp(0.0, 0.45);
    final rightFrac = (_rightMargin / baseW).clamp(0.0, 0.45);
    final bottomFrac = (_bottomMargin / baseH).clamp(0.0, 0.45);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live Preview',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${remainingW.toStringAsFixed(0)} × ${remainingH.toStringAsFixed(0)} pt',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Visual crop box overlay shows the active visible area.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),

          // Document Simulation Canvas
          Center(
            child: Container(
              width: 240,
              height: 339, // standard 1 : 1.414 aspect ratio
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF21262D) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
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
              child: Stack(
                children: [
                  // Real Page Content / Preview Background
                  Positioned.fill(
                    child: _buildCropPageBackground(isDark),
                  ),

                  // Cropped Viewport Box (Inside)
                  Positioned(
                    left: 240 * leftFrac,
                    top: 339 * topFrac,
                    right: 240 * rightFrac,
                    bottom: 339 * bottomFrac,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF0284C7),
                          width: 2.0,
                        ),
                        color: const Color(0xFF0284C7).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Stack(
                        children: [
                          // Top-Left Corner Mark
                          const Positioned(
                            left: 0,
                            top: 0,
                            child: Icon(Icons.crop_free_rounded, size: 14, color: Color(0xFF0284C7)),
                          ),
                          // Bottom-Right Corner Mark
                          const Positioned(
                            right: 0,
                            bottom: 0,
                            child: Icon(Icons.crop_free_rounded, size: 14, color: Color(0xFF0284C7)),
                          ),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'CROP VIEWPORT',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Grey region outside border will be trimmed.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161B22) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
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
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'PDF Cropped Successfully!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'Your PDF margins were trimmed non-destructively.',
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
                    const Icon(Icons.description_outlined, size: 18, color: Color(0xFF0284C7)),
                    const SizedBox(width: 8),
                    Text(
                      _resultFilename ?? 'document_cropped.pdf',
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
                      'Download Cropped PDF',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: _resetCrop,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Crop Again'),
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

  Widget _buildCropPageBackground(bool isDark) {
    final pageIndex = _targetPage - 1;
    final bytes = _thumbnailResult?.getPageBytes(pageIndex);
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildFallbackSkeleton(isDark),
        ),
      );
    }

    if (_isLoadingThumbnails) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0284C7)),
          ),
        ),
      );
    }

    return _buildFallbackSkeleton(isDark);
  }

  Widget _buildFallbackSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 12,
            width: 80,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < 9; i++) ...[
            Container(
              height: 6,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
