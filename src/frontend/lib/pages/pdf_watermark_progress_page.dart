import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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

/// Dedicated Status & Configuration Workspace for Watermark PDF (/watermark/process)
///
/// Ad Monetization Architecture:
/// - Dedicated route for Ad #2 (GAM 60s rotation).
/// - Dynamic text presets ("CONFIDENTIAL", "DRAFT", "DO NOT COPY", "SAMPLE").
/// - Real-time angle selector (-45°, 0°, 45°) & alpha opacity slider (10% - 100%).
/// - Image logo uploader with PNG alpha channel support.
/// - Live Document Preview Box dynamically mirroring angle and transparency.
/// - In-memory client download for instant output retrieval with Ad #3.
class PdfWatermarkProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfWatermarkProgressPage({super.key, this.file});

  @override
  State<PdfWatermarkProgressPage> createState() => _PdfWatermarkProgressPageState();
}

class _PdfWatermarkProgressPageState extends State<PdfWatermarkProgressPage> {
  SelectedPdfFile? _file;
  int _detectedPages = 1;
  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnails = false;
  bool _isUploadingThumbnails = false;
  int _thumbnailSentBytes = 0;
  int _thumbnailTotalBytes = 0;

  // Watermark Configuration
  String _watermarkType = 'text'; // 'text' or 'image'

  // Text Watermark Options
  String _selectedPreset = 'CONFIDENTIAL';
  final TextEditingController _customTextController = TextEditingController(text: 'CONFIDENTIAL');
  double _rotation = -45.0; // -45.0, 0.0, 45.0
  double _opacity = 0.3; // 0.1 to 1.0
  double _fontSize = 48.0;

  // Image Watermark Options
  Uint8List? _logoBytes;
  String? _logoFilename;

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
      '/watermark/process',
      pageTitle: 'FreePDFToolz — Watermark PDF',
    );
    AppLimitsConfig.ensureLoaded();

    if (_file != null) {
      _initDocumentState(_file!);
    }
  }

  @override
  void dispose() {
    _customTextController.dispose();
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

  String get _activeText {
    final t = _customTextController.text.trim();
    return t.isNotEmpty ? t : 'CONFIDENTIAL';
  }

  Future<void> _pickLogoImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final f = result.files.first;
        setState(() {
          _logoBytes = f.bytes;
          _logoFilename = f.name;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to select logo image: $e';
      });
    }
  }

  Future<void> _applyWatermark() async {
    if (_file == null || _file!.bytes == null) return;
    if (_watermarkType == 'image' && _logoBytes == null) {
      setState(() {
        _errorMessage = 'Please select a logo image before applying watermark.';
      });
      return;
    }

    final sessionFileId = _thumbnailResult?.sessionFileId;
    final bool useStagedFile = sessionFileId != null && sessionFileId.isNotEmpty;

    final files = <UploadFileItem>[];
    int totalBytes = 0;

    final fields = <String, String>{
      'watermark_type': _watermarkType,
      'rotation': _rotation.toString(),
      'opacity': _opacity.toString(),
      'font_size': _fontSize.toString(),
    };

    if (useStagedFile) {
      fields['session_file_id'] = sessionFileId;
      totalBytes = 1;
    } else {
      files.add(
        UploadFileItem(
          field: 'file',
          filename: _file!.name,
          bytes: _file!.bytes!,
        ),
      );
      totalBytes = _file!.bytes!.length;
    }

    if (_watermarkType == 'text') {
      fields['text'] = _activeText;
    } else if (_watermarkType == 'image' && _logoBytes != null) {
      files.add(
        UploadFileItem(
          field: 'image',
          filename: _logoFilename ?? 'logo.png',
          bytes: _logoBytes!,
        ),
      );
      totalBytes += _logoBytes!.length;
    }

    setState(() {
      _isProcessing = true;
      _isUploading = true;
      _uploadSentBytes = 0;
      _uploadTotalBytes = totalBytes;
      _errorMessage = null;
    });

    try {
      final uploadRes = await ApiService.uploadToolFiles(
        endpoint: '/tools/watermark',
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
        final outName = uploadRes.filename ?? '${rawStem}_watermarked.pdf';

        setState(() {
          _resultBytes = uploadRes.bytes;
          _resultFilename = outName;
          _isProcessing = false;
          _isUploading = false;
        });

        TelemetryService.trackEvent('watermark_completed', {
          'filename': _file!.name,
          'pages': _detectedPages,
          'type': _watermarkType,
        });
      } else {
        String detail = 'Watermarking failed with status ${uploadRes.statusCode}';
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

  void _resetWatermark() {
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
      appBar: const AppHeader(currentRoute: '/watermark'),
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
                    // Back link to tool landing
                    InkWell(
                      onTap: () => Navigator.pushReplacementNamed(context, '/watermark'),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                              color: isDark ? const Color(0xFF58A6FF) : const Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Back to Watermark PDF',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF58A6FF) : const Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // AdSense Banner #2 (Workspace Placement with 60s rotation)
                    const AdSenseBanner(),
                    const SizedBox(height: 24),

                    // Document Overview Card
                    if (_file != null) _buildDocumentHeaderCard(isDark),

                    if (_isLoadingThumbnails) ...[
                      const SizedBox(height: 16),
                      ToolUploadProgressIndicator(
                        sentBytes: _thumbnailSentBytes,
                        totalBytes: _thumbnailTotalBytes,
                        isUploading: _isUploadingThumbnails,
                        processingLabel: 'Generating page thumbnails...',
                        accentColor: const Color(0xFF2563EB),
                      ),
                    ],

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // If completed, show result view; otherwise show workspace configurator
                    if (_resultBytes != null)
                      _buildResultCard(isDark)
                    else if (!_isUploadingThumbnails)
                      _buildConfiguratorLayout(isDark),
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

  Widget _buildDocumentHeaderCard(bool isDark) {
    final sizeKb = ((_file?.sizeBytes ?? 0) / 1024).toStringAsFixed(1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF3B82F6), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _file?.name ?? 'Document.pdf',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    Text(
                      '$_detectedPages Pages',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      '•',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      ),
                    ),
                    Text(
                      '$sizeKb KB',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushReplacementNamed(context, '/watermark'),
            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
            label: const Text('Change File', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              side: BorderSide(
                color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfiguratorLayout(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Configuration Controls
              Expanded(
                flex: 6,
                child: _buildControlsPanel(isDark),
              ),
              const SizedBox(width: 24),
              // Right Column: Live Document Preview
              Expanded(
                flex: 5,
                child: _buildPreviewPanel(isDark),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              _buildPreviewPanel(isDark),
              const SizedBox(height: 24),
              _buildControlsPanel(isDark),
            ],
          );
        }
      },
    );
  }

  Widget _buildControlsPanel(bool isDark) {
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
          // Header: Mode Switcher Tabs
          Text(
            'Watermark Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),

          // Segmented tab switch: Text vs Image
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    label: 'Text Watermark',
                    icon: Icons.text_fields_rounded,
                    isActive: _watermarkType == 'text',
                    onTap: () => setState(() => _watermarkType = 'text'),
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: _buildTabButton(
                    label: 'Image Logo',
                    icon: Icons.image_rounded,
                    isActive: _watermarkType == 'image',
                    onTap: () => setState(() => _watermarkType = 'image'),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_watermarkType == 'text') ...[
            // Preset Chips
            Text(
              'Preset Text',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['CONFIDENTIAL', 'DRAFT', 'DO NOT COPY', 'SAMPLE'].map((preset) {
                final isSelected = _selectedPreset == preset && _customTextController.text == preset;
                return ChoiceChip(
                  label: Text(preset, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedPreset = preset;
                        _customTextController.text = preset;
                      });
                    }
                  },
                  selectedColor: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                  backgroundColor: isDark ? const Color(0xFF21262D) : const Color(0xFFF8FAFC),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : (isDark ? Colors.white70 : const Color(0xFF475569)),
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : (isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 18),

            // Custom Text Field
            Text(
              'Custom Text',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('watermark_custom_text_field'),
              controller: _customTextController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Enter custom watermark text',
                filled: true,
                fillColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 20),

            // Angle Selector Chips (-45°, 0°, 45°)
            Text(
              'Rotation Angle',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildAngleChip(
                  keyStr: 'angle_minus_45',
                  label: 'Diagonal (-45°)',
                  angle: -45.0,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildAngleChip(
                  keyStr: 'angle_0',
                  label: 'Horizontal (0°)',
                  angle: 0.0,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildAngleChip(
                  keyStr: 'angle_45',
                  label: 'Diagonal (45°)',
                  angle: 45.0,
                  isDark: isDark,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Font Size Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Font Size',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                Text(
                  '${_fontSize.toInt()} pt',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            Slider(
              value: _fontSize,
              min: 24.0,
              max: 96.0,
              divisions: 12,
              activeColor: const Color(0xFF3B82F6),
              onChanged: (val) => setState(() => _fontSize = val),
            ),
          ] else ...[
            // Image Mode Controls
            Text(
              'Select Logo Image',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickLogoImage,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _logoBytes != null ? Icons.check_circle_rounded : Icons.add_photo_alternate_outlined,
                      color: _logoBytes != null ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                      size: 36,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _logoFilename ?? 'Select Logo Image (PNG / JPG)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Supports transparent PNG and JPG logos',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Opacity Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Opacity: ${(_opacity * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              Text(
                _opacity <= 0.3 ? 'Subtle' : (_opacity <= 0.6 ? 'Balanced' : 'Prominent'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          Slider(
            value: _opacity,
            min: 0.1,
            max: 1.0,
            divisions: 18,
            activeColor: const Color(0xFF3B82F6),
            onChanged: (val) => setState(() => _opacity = val),
          ),

          const SizedBox(height: 24),

          if (_isProcessing) ...[
            ToolUploadProgressIndicator(
              isUploading: _isUploading,
              sentBytes: _uploadSentBytes,
              totalBytes: _uploadTotalBytes,
              processingLabel: 'Overlaying watermark layers in RAM disk...',
            ),
            const SizedBox(height: 16),
          ],

          // Primary Apply Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _applyWatermark,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.branding_watermark_rounded, size: 20),
              label: Text(
                _isProcessing
                    ? (_isUploading ? 'Uploading Watermark Assets...' : 'Applying Watermark...')
                    : 'Apply Watermark',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? const Color(0xFF30363D) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive
                  ? const Color(0xFF3B82F6)
                  : (isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? (isDark ? Colors.white : const Color(0xFF1E293B))
                    : (isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAngleChip({
    required String keyStr,
    required String label,
    required double angle,
    required bool isDark,
  }) {
    final isSelected = (_rotation == angle);

    return Expanded(
      child: InkWell(
        key: Key(keyStr),
        onTap: () => setState(() => _rotation = angle),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF3B82F6)
                  : (isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF3B82F6)
                  : (isDark ? Colors.white70 : const Color(0xFF475569)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPanel(bool isDark) {
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
              Expanded(
                child: Text(
                  'Live Document Preview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'REAL-TIME',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10B981),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Miniature Paper Preview Box
          Center(
            child: Container(
              key: const Key('live_preview_box'),
              width: 260,
              height: 368, // ~A4 aspect ratio
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF21262D) : const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    // Real page preview background with fallback
                    Positioned.fill(
                      child: _buildWatermarkPageBackground(isDark),
                    ),


                    // Centered Watermark Overlay with Angle and Opacity
                    Center(
                      child: _watermarkType == 'text'
                          ? Transform.rotate(
                              angle: _rotation * math.pi / 180.0,
                              child: Opacity(
                                opacity: _opacity.clamp(0.05, 1.0),
                                child: Text(
                                  _activeText,
                                  style: TextStyle(
                                    fontSize: (_fontSize * 0.45).clamp(14.0, 36.0),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                    color: const Color(0xFF64748B),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : Opacity(
                              opacity: _opacity.clamp(0.05, 1.0),
                              child: _logoBytes != null
                                  ? Image.memory(
                                      _logoBytes!,
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.contain,
                                    )
                                  : Icon(
                                      Icons.branding_watermark_rounded,
                                      size: 80,
                                      color: const Color(0xFF94A3B8),
                                    ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Center(
            child: Text(
              'Simulated Page 1 of $_detectedPages',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(bool isDark) {
    final sizeKb = ((_resultBytes?.lengthInBytes ?? 0) / 1024).toStringAsFixed(1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
          ),
          const SizedBox(height: 18),
          Text(
            'Watermark Applied Successfully!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your document was watermarked across all $_detectedPages pages.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // File Summary Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.description_outlined, color: Color(0xFF3B82F6), size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    _resultFilename ?? 'Watermarked.pdf',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '$sizeKb KB',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Action Buttons: Download and Reset
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  if (_resultBytes != null && _resultFilename != null) {
                    DownloadHelper.triggerDownloadBytes(_resultBytes!, _resultFilename!);
                  }
                },
                icon: const Icon(Icons.download_rounded, size: 20),
                label: const Text(
                  'Download Watermarked PDF',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _resetWatermark,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Watermark Another PDF', style: TextStyle(fontSize: 14)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // AdSense Banner #3 (Download Placement)
          const AdSenseBanner(),
        ],
      ),
    );
  }

  Widget _buildWatermarkPageBackground(bool isDark) {
    final thumb = _thumbnailResult?.getPage(1);
    if (thumb != null) {
      return Image.memory(
        thumb.imageBytes,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
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
            width: 140,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(9, (idx) {
            final wFactor = (idx % 3 == 0) ? 0.9 : (idx % 2 == 0 ? 0.75 : 0.85);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Container(
                height: 6,
                width: 220 * wFactor,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF30363D) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

