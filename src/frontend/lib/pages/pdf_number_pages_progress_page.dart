import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/adsense_banner.dart';
import '../utils/app_limits_config.dart';
import '../services/telemetry_service.dart';
import '../services/download_helper.dart';
import '../services/api_service.dart';
import '../services/pdf_thumbnail_service.dart';
import 'pdf_merge_page.dart' show SelectedPdfFile;

/// Dedicated Status & Progress Page for PDF Number Pages (/number-pages/process)
///
/// Ad Monetization Architecture:
/// - Dedicated route for Ad #2 (GAM 60s rotation).
/// - 3x3 Position Grid Selector with 6 selectable anchor points.
/// - Flexible format presets ('Page {n} of {total}', '{n}', 'Page {n}', '- {n} -') and custom template.
/// - Cover page skipping switch & starting number stepper.
/// - Live document preview box showing real-time text and positioning.
/// - In-memory client download for instant output retrieval with Ad #3.
class PdfNumberPagesProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfNumberPagesProgressPage({super.key, this.file});

  @override
  State<PdfNumberPagesProgressPage> createState() => _PdfNumberPagesProgressPageState();
}

class _PdfNumberPagesProgressPageState extends State<PdfNumberPagesProgressPage> {
  SelectedPdfFile? _file;
  int _detectedPages = 1;
  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnails = false;

  // Numbering Configuration
  String _selectedPosition = 'bottom-center';
  String _selectedFormat = 'Page {n} of {total}';
  final TextEditingController _customFormatController = TextEditingController();
  bool _isCustomFormat = false;
  bool _skipCover = false;
  int _startNumber = 1;
  double _fontSize = 10.0;

  bool _isSaving = false;
  String? _errorMessage;

  // Generated Result
  Uint8List? _resultBytes;
  String? _resultFilename;

  @override
  void initState() {
    super.initState();
    _file = widget.file;

    TelemetryService.trackPageView(
      '/number-pages/process',
      pageTitle: 'FreePDFToolz — Number Pages',
    );
    AppLimitsConfig.ensureLoaded();

    if (_file != null) {
      _initDocumentState(_file!);
    }
  }

  @override
  void dispose() {
    _customFormatController.dispose();
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
    setState(() => _isLoadingThumbnails = true);
    final result = await PdfThumbnailService.fetchThumbnails(file);
    if (!mounted) return;
    setState(() {
      _thumbnailResult = result;
      _isLoadingThumbnails = false;
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

  String get _activeFormatString {
    if (_isCustomFormat && _customFormatController.text.trim().isNotEmpty) {
      return _customFormatController.text.trim();
    }
    return _selectedFormat;
  }

  String _getPreviewText() {
    final effectiveTotal = _skipCover && _detectedPages > 1
        ? _startNumber + (_detectedPages - 1) - 1
        : _startNumber + _detectedPages - 1;

    final effectiveN = _startNumber;

    return _activeFormatString
        .replaceAll('{n}', effectiveN.toString())
        .replaceAll('{total}', effectiveTotal.toString());
  }

  Alignment _getAlignmentForPosition(String pos) {
    switch (pos) {
      case 'top-left':
        return Alignment.topLeft;
      case 'top-center':
        return Alignment.topCenter;
      case 'top-right':
        return Alignment.topRight;
      case 'bottom-left':
        return Alignment.bottomLeft;
      case 'bottom-right':
        return Alignment.bottomRight;
      case 'bottom-center':
      default:
        return Alignment.bottomCenter;
    }
  }

  Future<void> _executeNumberPages() async {
    if (_file == null || _file!.bytes == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/tools/number-pages');
      final request = http.MultipartRequest('POST', uri);

      request.fields['position'] = _selectedPosition;
      request.fields['format'] = _activeFormatString;
      request.fields['skip_cover'] = _skipCover.toString();
      request.fields['start_page'] = _startNumber.toString();
      request.fields['font_size'] = _fontSize.toString();

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          _file!.bytes!,
          filename: _file!.name,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final cleanBase = _file!.name.replaceAll('.pdf', '');
        String downloadName = '${cleanBase}_numbered.pdf';

        final disposition = response.headers['content-disposition'];
        if (disposition != null && disposition.contains('filename=')) {
          final regex = RegExp(r'filename=["' "'" r']?([^"' "'" r';\r\n]+)');
          final match = regex.firstMatch(disposition);
          if (match != null && match.group(1) != null) {
            downloadName = match.group(1)!.trim();
          }
        }


        setState(() {
          _resultBytes = response.bodyBytes;
          _resultFilename = downloadName;
          _isSaving = false;
        });

        TelemetryService.trackEvent('pdf_number_pages_completed', {
          'position': _selectedPosition,
          'format': _activeFormatString,
          'skip_cover': _skipCover,
          'start_number': _startNumber,
          'total_pages': _detectedPages,
          'output_size_bytes': response.bodyBytes.length,
          'filename': downloadName,
        });
      } else {
        String detail = 'Number pages operation failed (HTTP ${response.statusCode})';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded['detail'] != null) detail = decoded['detail'];
        } catch (_) {}
        setState(() {
          _errorMessage = detail;
          _isSaving = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error during number pages operation: $e';
        _isSaving = false;
      });
    }
  }

  void _downloadResult() {
    if (_resultBytes == null || _resultFilename == null) return;
    TelemetryService.trackDownloadClicked(
      jobId: 'number_${DateTime.now().millisecondsSinceEpoch}',
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
      Navigator.pushReplacementNamed(context, '/number-pages');
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
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      appBar: const AppHeader(currentRoute: '/number-pages'),
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
                    // AdSense Banner #2 (Status & Config Placement with 60s refresh)
                    const AdSenseBanner(),
                    const SizedBox(height: 24),

                    if (_file == null) ...[
                      _buildNoFilePlaceholder(isDark),
                    ] else ...[
                      // Document overview card
                      _buildDocumentOverviewCard(isDark),
                      const SizedBox(height: 24),

                      if (_resultBytes != null) ...[
                        // Success Download Card (Ad #3)
                        _buildDownloadCard(isDark),
                        const SizedBox(height: 24),
                      ],

                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 20),
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

                      // Two-column layout: Configurator & Live Preview
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 768;
                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: _buildConfiguratorCard(isDark),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 4,
                                  child: _buildLivePreviewCard(isDark),
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                _buildConfiguratorCard(isDark),
                                const SizedBox(height: 24),
                                _buildLivePreviewCard(isDark),
                              ],
                            );
                          }
                        },
                      ),

                      const SizedBox(height: 28),

                      // Apply Button
                      _buildActionButtons(isDark),
                    ],
                  ],
                ),
              ),
            ),
            const AppFooter(currentRoute: '/number-pages'),
          ],
        ),
      ),
    );
  }

  Widget _buildNoFilePlaceholder(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 48, color: Color(0xFFF59E0B)),
          const SizedBox(height: 16),
          Text(
            'No PDF file selected',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please return to the landing page and choose a PDF file to number.',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _resetAndGoBack,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
            ),
            child: const Text('Go to Number Pages'),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentOverviewCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Color(0xFF4F46E5),
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
                Wrap(
                  spacing: 12,
                  children: [
                    Text(
                      '$_detectedPages Pages',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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
                      _formatFileSize(_file!.sizeBytes),
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
            onPressed: _resetAndGoBack,
            icon: const Icon(Icons.change_circle_outlined, size: 18),
            label: const Text('Change File'),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              side: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfiguratorCard(bool isDark) {
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
            children: [
              const Icon(Icons.tune_rounded, color: Color(0xFF4F46E5), size: 22),
              const SizedBox(width: 10),
              Text(
                'Numbering Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 1. Position Matrix (3x3 grid)
          Text(
            'Placement Position',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 10),
          _buildPositionMatrix(isDark),

          const SizedBox(height: 24),

          // 2. Format Template Selector
          Text(
            'Format Style',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 10),
          _buildFormatSelector(isDark),

          const SizedBox(height: 24),

          // 3. Skip Cover Page Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Skip First Page / Cover Page',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Leaves page 1 unnumbered and starts on page 2',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _skipCover,
                  activeTrackColor: const Color(0xFF4F46E5),
                  onChanged: (val) {
                    setState(() {
                      _skipCover = val;
                    });
                  },
                ),

              ],
            ),
          ),

          const SizedBox(height: 20),

          // 4. Starting Page Number & Font Size
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Number',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.remove, size: 18),
                            onPressed: _startNumber > 1
                                ? () => setState(() => _startNumber--)
                                : null,
                          ),
                          Text(
                            '$_startNumber',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.add, size: 18),
                            onPressed: () => setState(() => _startNumber++),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Font Size (${_fontSize.toInt()}pt)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: _fontSize,
                          isExpanded: true,
                          dropdownColor: isDark ? const Color(0xFF161B22) : Colors.white,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                          items: const [
                            DropdownMenuItem(value: 8.0, child: Text('8 pt (Small)')),
                            DropdownMenuItem(value: 10.0, child: Text('10 pt (Standard)')),
                            DropdownMenuItem(value: 12.0, child: Text('12 pt (Medium)')),
                            DropdownMenuItem(value: 14.0, child: Text('14 pt (Large)')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _fontSize = val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPositionMatrix(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildPositionAnchor('top-left', 'Top Left', Icons.align_horizontal_left_rounded, isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildPositionAnchor('top-center', 'Top Center', Icons.align_horizontal_center_rounded, isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildPositionAnchor('top-right', 'Top Right', Icons.align_horizontal_right_rounded, isDark)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Document Content Area',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildPositionAnchor('bottom-left', 'Bottom Left', Icons.align_horizontal_left_rounded, isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildPositionAnchor('bottom-center', 'Bottom Center', Icons.align_horizontal_center_rounded, isDark)),
              const SizedBox(width: 8),
              Expanded(child: _buildPositionAnchor('bottom-right', 'Bottom Right', Icons.align_horizontal_right_rounded, isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPositionAnchor(String pos, String label, IconData icon, bool isDark) {
    final isSelected = _selectedPosition == pos;

    return InkWell(
      key: Key('pos_$pos'),
      onTap: () {
        setState(() {
          _selectedPosition = pos;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4F46E5).withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF161B22) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4F46E5)
                : (isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? const Color(0xFF4F46E5)
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF4F46E5))
                    : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatSelector(bool isDark) {
    final formats = [
      'Page {n} of {total}',
      '{n}',
      'Page {n}',
      '- {n} -',
    ];

    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: formats.map((fmt) {
            final isSelected = !_isCustomFormat && _selectedFormat == fmt;
            return ChoiceChip(
              label: Text(fmt),
              selected: isSelected,
              selectedColor: const Color(0xFF4F46E5),
              backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
              ),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFF4F46E5)
                    : (isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _isCustomFormat = false;
                    _selectedFormat = fmt;
                  });
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLivePreviewCard(bool isDark) {
    final previewAlign = _getAlignmentForPosition(_selectedPosition);
    final previewText = _getPreviewText();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.remove_red_eye_outlined, color: Color(0xFF4F46E5), size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Live Document Preview',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Text(
            _skipCover ? 'Showing Page 2 (First Numbered Page)' : 'Showing Page 1',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),

          // Miniature A4 page preview (Real page thumbnail + numbering overlay)
          Container(
            key: const Key('live_preview_box'),
            width: 220,
            height: 310,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildNumberingPageBackground(isDark),
                  ),

                  // Live Number Position Overlay
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: previewAlign,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          previewText,
                          style: TextStyle(
                            fontSize: _fontSize,
                            fontFamily: 'Helvetica',
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Sample: $previewText',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberingPageBackground(bool isDark) {
    final pageNum = (_skipCover && _detectedPages > 1) ? 2 : 1;
    final thumb = _thumbnailResult?.getPage(pageNum);
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Container(height: 8, width: 80, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 12),
          Container(height: 6, width: 180, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 8),
          Container(height: 6, width: 160, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 8),
          Container(height: 6, width: 170, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 18),
          Container(height: 6, width: 175, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 8),
          Container(height: 6, width: 150, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 8),
          Container(height: 6, width: 165, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3))),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, minHeight: 48),
        child: ElevatedButton(
          onPressed: _isSaving ? null : _executeNumberPages,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          child: _isSaving
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Applying Numbers...',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.format_list_numbered_rounded, size: 20),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Apply Page Numbers',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }


  Widget _buildDownloadCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Page Numbers Successfully Applied!',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _resultFilename ?? 'Numbered document ready for download',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Ad #3 Placement inside completion container
          const AdSenseBanner(),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _downloadResult,
                  icon: const Icon(Icons.file_download_rounded, size: 20),
                  label: const Text('Download Numbered PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _resetAndGoBack,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Number Another'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                  side: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
