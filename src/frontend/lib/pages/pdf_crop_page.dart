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

/// Tool Landing Page for Crop PDF (/crop)
///
/// Ad Monetization Architecture:
/// - Displays Tool Landing Ad (Ad #1).
/// - Dynamic limit copy strictly sourced from canonical AppLimitsConfig. Zero hardcoded limits.
/// - Action-Driven Navigation: Dropping or selecting a PDF immediately transitions to
///   the dedicated status/progress route (/crop/process) where Ad #2 lives.
class PdfCropPage extends StatefulWidget {
  final SelectedPdfFile? initialFile;

  const PdfCropPage({super.key, this.initialFile});

  @override
  State<PdfCropPage> createState() => _PdfCropPageState();
}

class _PdfCropPageState extends State<PdfCropPage> {
  bool _isDragging = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    TelemetryService.trackPageView(
      '/crop',
      pageTitle: 'FreePDFToolz — Crop PDF',
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

      if (userWatchedAd && boostedLimit != null) {
        setState(() {}); // refresh after boost
      } else {
        setState(() {
          _errorMessage =
              'File "$name" (${(size / (1024 * 1024)).toStringAsFixed(1)} MB) exceeds the current limit of ${AppLimitsConfig.activeLimitMb.toStringAsFixed(0)} MB.';
        });
        break;
      }
    }
  }

  void _navigateToProcess(SelectedPdfFile file) {
    Navigator.pushNamed(
      context,
      '/crop/process',
      arguments: {'file': file},
    );
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
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                child: Column(
                  children: [
                    // Tool Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.crop_rounded,
                        size: 48,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Crop PDF',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Text(
                        'Trim page margins or select custom viewport boundaries for your PDF. Non-destructive PyMuPDF engine preserves vectors and text layers.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Ad #1: Top of Landing Page
                    const AdSenseBanner(),
                    const SizedBox(height: 32),

                    // Error Notification if any
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

                    // Dropzone Container
                    DropTarget(
                      onDragEntered: (_) => setState(() => _isDragging = true),
                      onDragExited: (_) => setState(() => _isDragging = false),
                      onDragDone: _handleDrop,
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxWidth: 700),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? const Color(0xFF0284C7).withOpacity(0.08)
                              : (isDark ? const Color(0xFF161B22) : Colors.white),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isDragging
                                ? const Color(0xFF0284C7)
                                : (isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
                            width: _isDragging ? 2.5 : 1.5,
                            style: BorderStyle.solid,
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
                                color: const Color(0xFF0284C7).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cloud_upload_outlined,
                                size: 48,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Drop PDF file here',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Select a PDF to trim and adjust margins visually',
                              style: TextStyle(
                                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.file_open_rounded, color: Colors.white),
                              label: const Text(
                                'Select PDF File',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF21262D) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                AppLimitsConfig.dropzoneNoticeText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 64),

                    // Feature Showcase Cards
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildFeatureCard(
                              context,
                              icon: Icons.aspect_ratio_rounded,
                              title: 'Precision Margin Control',
                              description:
                                  'Adjust top, bottom, left, and right margins with live point sliders and instant preset options.',
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: _buildFeatureCard(
                              context,
                              icon: Icons.layers_rounded,
                              title: 'Non-Destructive Crop',
                              description:
                                  'Standard PDF /CropBox updates preserve underlying text and vector graphics for searchability.',
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: _buildFeatureCard(
                              context,
                              icon: Icons.filter_none_rounded,
                              title: 'Scope Flexibility',
                              description:
                                  'Crop all pages uniformly or apply targeted boundary adjustments to an individual page.',
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 64),

                    // FAQ Accordion
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Frequently Asked Questions',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 16),
                          _buildFaqItem(
                            question: 'Does cropping delete the text or images from my PDF?',
                            answer:
                                'No. Cropping in PDF sets a visible boundary (/CropBox). The original text and vector graphics remain fully intact, searchable, and intact within the document structure.',
                            isDark: isDark,
                          ),
                          const SizedBox(height: 14),
                          _buildFaqItem(
                            question: 'Can I crop only one specific page?',
                            answer:
                                'Yes. You can choose "Apply to all pages" or toggle off to select an individual page number to crop.',
                            isDark: isDark,
                          ),
                          const SizedBox(height: 14),
                          _buildFaqItem(
                            question: 'Are my uploaded files kept private?',
                            answer:
                                '100% private. Files are processed in temporary RAM storage and automatically purged immediately after download generation.',
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
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

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF0284C7), size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqItem({
    required String question,
    required String answer,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          answer,
          style: TextStyle(
            color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
