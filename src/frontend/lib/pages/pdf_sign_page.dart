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
import 'pdf_merge_page.dart' show SelectedPdfFile;

/// Tool Landing Page for Sign PDF (/sign)
///
/// Ad Monetization Architecture:
/// - Displays Tool Landing Ad (Ad #1).
/// - Dynamic limit copy strictly sourced from canonical AppLimitsConfig. Zero hardcoded limits.
/// - Action-Driven Navigation: Dropping or selecting a PDF immediately transitions to
///   the dedicated status/progress route (/sign/process) where Ad #2 lives.
class PdfSignPage extends StatefulWidget {
  final SelectedPdfFile? initialFile;

  const PdfSignPage({super.key, this.initialFile});

  @override
  State<PdfSignPage> createState() => _PdfSignPageState();
}

class _PdfSignPageState extends State<PdfSignPage> {
  bool _isDragging = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    TelemetryService.trackPageView(
      '/sign',
      pageTitle: 'FreePDFToolz — Sign PDF',
    );
    AppLimitsConfig.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });

    if (widget.initialFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToProcess(widget.initialFile!);
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final f = result.files.first;
        await _processIncomingFile({
          'name': f.name,
          'size': f.size,
          'bytes': f.bytes,
          'path': kIsWeb ? null : f.path,
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to select PDF file: $e';
      });
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    for (final xfile in details.files) {
      if (xfile.name.toLowerCase().endsWith('.pdf')) {
        final length = await xfile.length();
        final bytes = await xfile.readAsBytes();
        await _processIncomingFile({
          'name': xfile.name,
          'size': length,
          'bytes': bytes,
          'path': kIsWeb ? null : xfile.path,
        });
        break; // Process first dropped PDF
      }
    }
  }

  Future<void> _processIncomingFile(Map<String, dynamic> item) async {
    final name = item['name'] as String;
    final size = item['size'] as int;
    final bytes = item['bytes'] as Uint8List?;
    final path = item['path'] as String?;

    if (size == 0) return;

    bool isAccepted = false;
    while (!isAccepted) {
      final limitEval = AppLimitsConfig.evaluate(size);

      if (!limitEval.isExceeded) {
        isAccepted = true;
        final selected = SelectedPdfFile(
          name: name,
          sizeBytes: size,
          bytes: bytes,
          path: path,
        );
        _navigateToProcess(selected);
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

  void _navigateToProcess(SelectedPdfFile file) {
    Navigator.of(context).pushNamed(
      '/sign/process',
      arguments: file,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: const AppHeader(currentRoute: '/sign'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  // Title & Subtitle
                  Text(
                    'Sign PDF',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Draw, type, or upload verifiable digital signatures to sign PDF documents.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Top Banner Ad (Ad #1)
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

                  // Dropzone Card
                  DropTarget(
                    onDragEntered: (_) => setState(() => _isDragging = true),
                    onDragExited: (_) => setState(() => _isDragging = false),
                    onDragDone: _handleDrop,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                      decoration: BoxDecoration(
                        color: _isDragging
                            ? theme.colorScheme.primary.withAlpha(20)
                            : (isDark ? Colors.grey[900] : Colors.grey[50]),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isDragging
                              ? theme.colorScheme.primary
                              : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
                          width: 2,
                          strokeAlign: BorderSide.strokeAlignInside,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.draw_rounded,
                            size: 64,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Drop PDF file here to sign',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'or click to browse from your device',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('Select PDF File'),
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
                          const SizedBox(height: 16),
                          // Dynamic limits badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[800] : Colors.grey[200],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 14,
                                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  AppLimitsConfig.dropzoneNoticeText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Feature Cards
                  _buildFeatureHighlights(theme, isDark),

                  const SizedBox(height: 48),

                  // How It Works & SEO Content
                  _buildEducationalGuide(theme, isDark),

                  const SizedBox(height: 48),

                  // FAQ Accordion
                  _buildFaqSection(theme, isDark),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 48),
        const AppFooter(currentRoute: '/sign'),
      ],
    ),
  ),
);
}

  Widget _buildFeatureHighlights(ThemeData theme, bool isDark) {
    final features = [
      {
        'icon': Icons.gesture_rounded,
        'title': 'Draw Signature',
        'desc': 'Interactive canvas pad with ultra-smooth vector curves for finger or stylus.',
      },
      {
        'icon': Icons.text_fields_rounded,
        'title': 'Type Name',
        'desc': 'Convert typed names into gorgeous cursive script signatures automatically.',
      },
      {
        'icon': Icons.image_rounded,
        'title': 'Upload Scan',
        'desc': 'Stamp existing transparent PNG signature scans without white box artifacts.',
      },
      {
        'icon': Icons.security_rounded,
        'title': '100% Private',
        'desc': 'Local vector execution. Files and signatures never stored or inspected.',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Why Sign PDFs with FreePDFToolz?',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 650;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 4 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                mainAxisExtent: 140,
              ),
              itemCount: features.length,
              itemBuilder: (context, index) {
                final item = features[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item['icon'] as IconData,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item['title'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          item['desc'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildEducationalGuide(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How to Electronically Sign PDF Documents Online',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Signing documents digitally shouldn\'t require expensive monthly subscriptions or printing and re-scanning sheets of paper. FreePDFToolz provides a lightning-fast, zero-friction electronic signature workflow directly in your web browser. Choose whether to draw your signature with mouse or touch, type your name using elegant cursive calligraphy, or upload an existing signature stamp scan.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? Colors.grey[300] : Colors.grey[700],
            height: 1.6,
          ),
        ),
        const SizedBox(height: 16),
        _buildStepItem('1', 'Upload PDF Document', 'Drag and drop contracts, NDAs, invoices, or application forms.'),
        _buildStepItem('2', 'Create Your Signature', 'Draw, type cursive text, or upload a transparent PNG signature scan.'),
        _buildStepItem('3', 'Select Page & Position', 'Choose target page, drag the signature box to the signature line, and adjust scale.'),
        _buildStepItem('4', 'Download Signed PDF', 'Instant high-resolution vector stamping with zero quality loss or background artifacts.'),
      ],
    );
  }

  Widget _buildStepItem(String num, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(30),
            child: Text(
              num,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[400]
                        : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frequently Asked Questions',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildFaqItem(
          question: 'Is electronically signing a PDF document legally binding?',
          answer: 'In most jurisdictions worldwide (including the US ESIGN Act and EU eIDAS regulations), electronic signatures are recognized as legally binding for commercial contracts, service agreements, and acknowledgments.',
        ),
        _buildFaqItem(
          question: 'Are my signatures or confidential documents stored on your server?',
          answer: 'Never. FreePDFToolz processes all operations in transient ephemeral memory. Once your signed PDF is delivered to your browser, both the document and signature streams are permanently purged.',
        ),
        _buildFaqItem(
          question: 'Does applying a signature corrupt underlying searchable text or OCR?',
          answer: 'No. FreePDFToolz uses PyMuPDF vector overlays, ensuring all pre-existing text streams, embedded fonts, and OCR search indices remain 100% intact and selectable.',
        ),
      ],
    );
  }

  Widget _buildFaqItem({required String question, required String answer}) {
    return ExpansionTile(
      title: Text(
        question,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            answer,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[400]
                  : Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }
}
