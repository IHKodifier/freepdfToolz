import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../widgets/app_header.dart';
import '../widgets/adsense_banner.dart';
import '../services/telemetry_service.dart';
import '../services/api_service.dart';
import '../services/download_helper.dart';
import '../services/pdf_thumbnail_service.dart';
import 'pdf_merge_page.dart' show SelectedPdfFile;

/// Dedicated Status & Configuration Workspace for Sign PDF (/sign/process)
///
/// Ad Monetization Architecture:
/// - Displays Processing Ad (Ad #2) with GAM 60s auto-refresh.
/// - Upon successful signature application, reveals Result Ad (Ad #3).
class PdfSignProgressPage extends StatefulWidget {
  final SelectedPdfFile? file;

  const PdfSignProgressPage({super.key, this.file});

  @override
  State<PdfSignProgressPage> createState() => _PdfSignProgressPageState();
}

class _PdfSignProgressPageState extends State<PdfSignProgressPage> {
  SelectedPdfFile? _file;
  int _pageCount = 1;
  int _currentPage = 1; // 1-based index
  PdfThumbnailResult? _thumbnailResult;
  bool _isLoadingThumbnails = false;

  // Signature state
  Uint8List? _signatureBytes;

  // Placement parameters (in relative percentage 0.0 - 1.0)
  double _relativeX = 0.65; // default bottom-rightish
  double _relativeY = 0.80;
  double _relativeWidth = 0.25; // 25% of page width
  double _relativeHeight = 0.10; // 10% of page height

  // Standard PDF page dimensions in points (A4 default: 595 x 842)
  static const double _pdfPageWidth = 595.0;
  static const double _pdfPageHeight = 842.0;

  // Processing state
  bool _isProcessing = false;
  String? _errorMessage;
  Uint8List? _signedPdfBytes;

  @override
  void initState() {
    super.initState();
    TelemetryService.trackPageView(
      '/sign/process',
      pageTitle: 'FreePDFToolz — Sign PDF',
    );
    _file = widget.file;
    if (_file != null) {
      _detectPageCount();
    }
  }

  void _detectPageCount() {
    if (_file?.bytes == null) return;
    try {
      final text = String.fromCharCodes(_file!.bytes!);
      final regex = RegExp(r'/Type\s*/Page[^s]');
      final matches = regex.allMatches(text);
      if (matches.isNotEmpty) {
        setState(() {
          _pageCount = math.max(1, matches.length);
        });
        return;
      }
      final countRegex = RegExp(r'/Count\s+(\d+)');
      final countMatch = countRegex.firstMatch(text);
      if (countMatch != null) {
        final parsed = int.tryParse(countMatch.group(1) ?? '1') ?? 1;
        setState(() {
          _pageCount = math.max(1, parsed);
        });
      }
    } catch (_) {
      _pageCount = 1;
    }
    _loadThumbnails();
  }

  Future<void> _loadThumbnails() async {
    if (_file == null) return;
    setState(() => _isLoadingThumbnails = true);
    final result = await PdfThumbnailService.fetchThumbnails(_file!);
    if (!mounted) return;
    setState(() {
      _thumbnailResult = result;
      _isLoadingThumbnails = false;
      if (result.isSuccess && result.totalPages > 0) {
        _pageCount = result.totalPages;
      }
    });
  }

  Future<void> _openSignatureModal() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const SignatureCreationDialog(),
    );

    if (result != null && result['bytes'] != null) {
      setState(() {
        _signatureBytes = result['bytes'] as Uint8List;
        _errorMessage = null;
      });
    }
  }

  Future<void> _applySignature() async {
    if (_file == null || _file!.bytes == null) {
      setState(() => _errorMessage = 'No PDF file selected.');
      return;
    }

    if (_signatureBytes == null) {
      setState(() => _errorMessage = 'Please create or upload a signature before proceeding.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/tools/sign');
      final request = http.MultipartRequest('POST', uri);

      // Add PDF document
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          _file!.bytes!,
          filename: _file!.name,
        ),
      );

      // Add Signature PNG image
      request.files.add(
        http.MultipartFile.fromBytes(
          'signature',
          _signatureBytes!,
          filename: 'signature.png',
        ),
      );

      // Convert relative page coordinates to PDF point coordinates
      final targetX = _relativeX * _pdfPageWidth;
      final targetY = _relativeY * _pdfPageHeight;
      final targetWidth = _relativeWidth * _pdfPageWidth;
      final targetHeight = _relativeHeight * _pdfPageHeight;

      request.fields['page'] = _currentPage.toString();
      request.fields['x'] = targetX.toStringAsFixed(2);
      request.fields['y'] = targetY.toStringAsFixed(2);
      request.fields['width'] = targetWidth.toStringAsFixed(2);
      request.fields['height'] = targetHeight.toStringAsFixed(2);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        setState(() {
          _isProcessing = false;
          _signedPdfBytes = response.bodyBytes;
        });
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Server error (${response.statusCode}): ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Failed to apply signature: $e';
      });
    }
  }

  void _downloadSignedFile() {
    if (_signedPdfBytes == null || _file == null) return;
    final outName = 'signed_${_file!.name}';
    DownloadHelper.triggerDownloadBytes(
      _signedPdfBytes!,
      outName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_file == null) {
      return Scaffold(
        appBar: const AppHeader(currentRoute: '/sign'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No PDF file loaded.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushReplacementNamed('/sign'),
                child: const Text('Select a PDF to Sign'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const AppHeader(currentRoute: '/sign'),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Workspace Header
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pushReplacementNamed('/sign'),
                        tooltip: 'Back to Sign PDF',
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Sign PDF Workspace',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Processing Banner Ad (Ad #2)
                  const Center(
                    child: AdSenseBanner(),
                  ),
                  const SizedBox(height: 24),

                  // Error Display
                  if (_errorMessage != null) ...[
                    Container(
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
                    const SizedBox(height: 16),
                  ],

                  // Document Overview Card
                  _buildDocumentCard(theme, isDark),
                  const SizedBox(height: 24),

                  if (_signedPdfBytes != null)
                    // Result Download Card with Ad #3
                    _buildResultCard(theme, isDark)
                  else
                    // Interactive Signing & Placement Panel
                    _buildWorkspacePanel(theme, isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentCard(ThemeData theme, bool isDark) {
    final sizeKb = (_file!.sizeBytes / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 28),
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
                Text(
                  '$_pageCount Pages  •  $sizeKb KB',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushReplacementNamed('/sign'),
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
        final isWide = constraints.maxWidth > 750;

        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Placement Canvas Preview (Left 55%)
                  Expanded(
                    flex: 55,
                    child: _buildPlacementCanvas(theme, isDark),
                  ),
                  const SizedBox(width: 24),
                  // Signature & Coordinate Controls (Right 45%)
                  Expanded(
                    flex: 45,
                    child: _buildControlsCard(theme, isDark),
                  ),
                ],
              )
            : Column(
                children: [
                  _buildPlacementCanvas(theme, isDark),
                  const SizedBox(height: 24),
                  _buildControlsCard(theme, isDark),
                ],
              );
      },
    );
  }

  Widget _buildPlacementCanvas(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Page Navigation Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.grey[100],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sign on Page $_currentPage of $_pageCount',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Row(
                children: [
                  IconButton(
                    key: const Key('sign_prev_page_btn'),
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _currentPage > 1
                        ? () => setState(() => _currentPage--)
                        : null,
                    tooltip: 'Previous Page',
                  ),
                  Text('$_currentPage / $_pageCount'),
                  IconButton(
                    key: const Key('sign_next_page_btn'),
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _currentPage < _pageCount
                        ? () => setState(() => _currentPage++)
                        : null,
                    tooltip: 'Next Page',
                  ),
                ],
              ),
            ],
          ),
        ),

        // Miniature PDF Page Canvas Container
        Container(
          key: const Key('sign_placement_canvas'),
          height: 460,
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[950] : Colors.grey[200],
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            border: Border(
              left: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
              right: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
              bottom: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
            ),
          ),
          child: Center(
            child: AspectRatio(
              // Standard A4 aspect ratio 1 : 1.414 (595 / 842)
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
                  builder: (ctx, pageConstraints) {
                    final canvasW = pageConstraints.maxWidth;
                    final canvasH = pageConstraints.maxHeight;

                    final stampW = _relativeWidth * canvasW;
                    final stampH = _relativeHeight * canvasH;
                    final stampLeft = _relativeX * canvasW;
                    final stampTop = _relativeY * canvasH;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Real Page Background
                        Positioned.fill(
                          child: _buildSignPageBackground(isDark),
                        ),

                        // Draggable / Interactive Signature Stamp
                        Positioned(
                          left: stampLeft.clamp(0.0, math.max(0.0, canvasW - stampW)),
                          top: stampTop.clamp(0.0, math.max(0.0, canvasH - stampH)),
                          width: stampW,
                          height: stampH,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _relativeX = (_relativeX + details.delta.dx / canvasW)
                                    .clamp(0.0, 1.0 - _relativeWidth);
                                _relativeY = (_relativeY + details.delta.dy / canvasH)
                                    .clamp(0.0, 1.0 - _relativeHeight);
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.colorScheme.primary, width: 1.5),
                                color: theme.colorScheme.primary.withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: _signatureBytes != null
                                  ? Image.memory(
                                      _signatureBytes!,
                                      fit: BoxFit.contain,
                                    )
                                  : Center(
                                      child: Text(
                                        'Your Signature',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildControlsCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step 1: Signature Creation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '1. Signature',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_signatureBytes != null)
                const Chip(
                  label: Text('Ready', style: TextStyle(fontSize: 11, color: Colors.green)),
                  backgroundColor: Color(0x1A4CAF50),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Signature Preview or Open Modal Button
          if (_signatureBytes != null) ...[
            Container(
              height: 70,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
              ),
              child: Center(
                child: Image.memory(
                  _signatureBytes!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('open_signature_dialog_btn'),
              onPressed: _openSignatureModal,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Change Signature'),
            ),
          ] else ...[
            ElevatedButton.icon(
              key: const Key('open_signature_dialog_btn'),
              onPressed: _openSignatureModal,
              icon: const Icon(Icons.draw_rounded),
              label: const Text('Create / Change Signature'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],

          const Divider(height: 32),

          // Step 2: Placement & Dimensions
          Text(
            '2. Position & Size',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Quick Placement Presets
          Text(
            'Quick Align:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Bottom Right'),
                onPressed: () {
                  setState(() {
                    _relativeX = 0.65;
                    _relativeY = 0.82;
                  });
                },
              ),
              ActionChip(
                label: const Text('Bottom Left'),
                onPressed: () {
                  setState(() {
                    _relativeX = 0.10;
                    _relativeY = 0.82;
                  });
                },
              ),
              ActionChip(
                label: const Text('Center'),
                onPressed: () {
                  setState(() {
                    _relativeX = (1.0 - _relativeWidth) / 2;
                    _relativeY = (1.0 - _relativeHeight) / 2;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Scale Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Signature Width:', style: TextStyle(fontSize: 12)),
              Text('${(_relativeWidth * 100).toInt()}% of page', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: _relativeWidth,
            min: 0.10,
            max: 0.60,
            divisions: 10,
            onChanged: (val) {
              setState(() {
                _relativeWidth = val;
                // keep aspect ratio ~ 2.5:1
                _relativeHeight = val / 2.5;
                if (_relativeX + _relativeWidth > 1.0) {
                  _relativeX = 1.0 - _relativeWidth;
                }
                if (_relativeY + _relativeHeight > 1.0) {
                  _relativeY = 1.0 - _relativeHeight;
                }
              });
            },
          ),

          const SizedBox(height: 24),

          // Action Button
          ElevatedButton(
            onPressed: _isProcessing ? null : _applySignature,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Apply Signature',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withAlpha(20),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0x2A4CAF50),
                radius: 20,
                child: Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PDF Successfully Signed!',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Signature vector stamp applied to Page $_currentPage.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Download Button
          ElevatedButton.icon(
            onPressed: _downloadSignedFile,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download Signed PDF'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),

          OutlinedButton(
            onPressed: () {
              setState(() {
                _signedPdfBytes = null;
              });
            },
            child: const Text('Adjust Signature & Reprocess'),
          ),

          const SizedBox(height: 32),

          // Result Ad (Ad #3)
          const Center(
            child: AdSenseBanner(),
          ),
        ],
      ),
    );
  }

  Widget _buildSignPageBackground(bool isDark) {
    final pageIndex = _currentPage - 1;
    final bytes = _thumbnailResult?.getPageBytes(pageIndex);
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildFallbackDocumentLines(),
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
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
          ),
        ),
      );
    }

    return _buildFallbackDocumentLines();
  }

  Widget _buildFallbackDocumentLines() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 10, width: 90, color: Colors.grey[300]),
          const SizedBox(height: 14),
          for (int i = 0; i < 9; i++) ...[
            Container(
              height: 5,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 7),
              color: Colors.grey[200],
            ),
          ],
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(height: 1, width: 80, color: Colors.grey[400]),
              Container(height: 1, width: 80, color: Colors.grey[400]),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Date', style: TextStyle(fontSize: 8, color: Colors.grey[600])),
              Text('Authorized Signature', style: TextStyle(fontSize: 8, color: Colors.grey[600])),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Interactive Signature Creation Dialog (Draw, Type, Upload)
// -----------------------------------------------------------------------------

class SignatureCreationDialog extends StatefulWidget {
  const SignatureCreationDialog({super.key});

  @override
  State<SignatureCreationDialog> createState() => _SignatureCreationDialogState();
}

class _SignatureCreationDialogState extends State<SignatureCreationDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Draw State
  final List<Offset?> _points = [];
  Color _strokeColor = Colors.black;
  double _strokeWidth = 3.0;

  // Type State
  final TextEditingController _typeController = TextEditingController(text: 'John Doe');
  int _selectedFontStyleIndex = 0;

  // Upload State
  Uint8List? _uploadedBytes;
  String? _uploadedFileName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _typeController.dispose();
    super.dispose();
  }

  Future<void> _pickUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _uploadedBytes = result.files.first.bytes;
        _uploadedFileName = result.files.first.name;
      });
    }
  }

  Future<Uint8List?> _renderDrawnSignatureToPng() async {
    if (_points.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 160));

    final paint = Paint()
      ..color = _strokeColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _strokeWidth;

    for (int i = 0; i < _points.length - 1; i++) {
      if (_points[i] != null && _points[i + 1] != null) {
        canvas.drawLine(_points[i]!, _points[i + 1]!, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(400, 160);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<Uint8List?> _renderTypedSignatureToPng() async {
    final text = _typeController.text.trim();
    if (text.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 160));

    TextStyle textStyle;
    switch (_selectedFontStyleIndex) {
      case 1:
        textStyle = GoogleFonts.caveat(fontSize: 48, color: _strokeColor, fontWeight: FontWeight.w600);
        break;
      case 2:
        textStyle = GoogleFonts.sacramento(fontSize: 52, color: _strokeColor, fontWeight: FontWeight.w600);
        break;
      case 0:
      default:
        textStyle = GoogleFonts.dancingScript(fontSize: 48, color: _strokeColor, fontWeight: FontWeight.bold);
        break;
    }

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: 380);
    textPainter.paint(
      canvas,
      Offset(
        (400 - textPainter.width) / 2,
        (160 - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(400, 160);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _confirmSignature() async {
    Uint8List? resultBytes;
    String type = 'draw';

    if (_tabController.index == 0) {
      type = 'draw';
      resultBytes = await _renderDrawnSignatureToPng();
    } else if (_tabController.index == 1) {
      type = 'type';
      resultBytes = await _renderTypedSignatureToPng();
    } else if (_tabController.index == 2) {
      type = 'upload';
      resultBytes = _uploadedBytes;
    }

    if (resultBytes != null && mounted) {
      Navigator.of(context).pop({'bytes': resultBytes, 'type': type});
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw, type, or upload a signature.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Create Signature',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Tab Bar
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.gesture_rounded), text: 'Draw'),
                  Tab(icon: Icon(Icons.text_fields_rounded), text: 'Type'),
                  Tab(icon: Icon(Icons.upload_file_rounded), text: 'Upload'),
                ],
              ),
              const SizedBox(height: 16),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Draw Pad
                    _buildDrawTab(theme, isDark),
                    // Tab 2: Type Script
                    _buildTypeTab(theme, isDark),
                    // Tab 3: Upload Scan
                    _buildUploadTab(theme, isDark),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Dialog Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _confirmSignature,
                    child: const Text('Confirm & Use Signature'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawTab(ThemeData theme, bool isDark) {
    return Column(
      children: [
        // Color & Clear Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _buildColorCircle(Colors.black),
                const SizedBox(width: 8),
                _buildColorCircle(const Color(0xFF1565C0)), // Navy
                const SizedBox(width: 8),
                _buildColorCircle(const Color(0xFFC62828)), // Red
              ],
            ),
            TextButton.icon(
              onPressed: () => setState(() => _points.clear()),
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text('Clear Canvas'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Interactive Draw Canvas
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() => _points.add(details.localPosition));
                },
                onPanUpdate: (details) {
                  setState(() => _points.add(details.localPosition));
                },
                onPanEnd: (_) {
                  setState(() => _points.add(null));
                },
                child: CustomPaint(
                  painter: SignaturePainter(points: _points, strokeColor: _strokeColor, strokeWidth: _strokeWidth),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorCircle(Color color) {
    final isSelected = _strokeColor == color;
    return GestureDetector(
      onTap: () => setState(() => _strokeColor = color),
      child: CircleAvatar(
        radius: 12,
        backgroundColor: color,
        child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
      ),
    );
  }

  Widget _buildTypeTab(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('typed_signature_field'),
          controller: _typeController,
          decoration: const InputDecoration(
            labelText: 'Your Name / Signature Text',
            hintText: 'Enter name to generate cursive signature',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),

        Text(
          'Select Calligraphy Style:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: ListView(
            children: [
              _buildFontStyleTile(
                index: 0,
                name: 'Dancing Script',
                textStyle: GoogleFonts.dancingScript(fontSize: 28, color: _strokeColor),
              ),
              _buildFontStyleTile(
                index: 1,
                name: 'Caveat Script',
                textStyle: GoogleFonts.caveat(fontSize: 30, color: _strokeColor),
              ),
              _buildFontStyleTile(
                index: 2,
                name: 'Sacramento Elegance',
                textStyle: GoogleFonts.sacramento(fontSize: 32, color: _strokeColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFontStyleTile({
    required int index,
    required String name,
    required TextStyle textStyle,
  }) {
    final isSelected = _selectedFontStyleIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withAlpha(20)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]!
                  : Colors.grey[300]!),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          title: Text(
            _typeController.text.isEmpty ? 'Your Signature' : _typeController.text,
            style: textStyle,
          ),
          subtitle: Text(name, style: const TextStyle(fontSize: 11)),
          trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
          onTap: () => setState(() => _selectedFontStyleIndex = index),
        ),
      ),
    );
  }

  Widget _buildUploadTab(ThemeData theme, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_uploadedBytes != null) ...[
          Container(
            height: 100,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green),
            ),
            child: Image.memory(_uploadedBytes!, fit: BoxFit.contain),
          ),
          const SizedBox(height: 12),
          Text(
            _uploadedFileName ?? 'Signature file loaded',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
        ],
        ElevatedButton.icon(
          onPressed: _pickUploadFile,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Select Signature Image (PNG / JPG)'),
        ),
        const SizedBox(height: 12),
        Text(
          'Upload transparent PNG for crisp, high-quality results.',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Signature Drawing Painter
// -----------------------------------------------------------------------------

class SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  final Color strokeColor;
  final double strokeWidth;

  SignaturePainter({
    required this.points,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = strokeColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
