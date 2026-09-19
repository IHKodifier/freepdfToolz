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

/// Tool Landing Page for Annotate PDF (/annotate)
///
/// Ad Monetization Architecture:
/// - Displays Tool Landing Ad (Ad #1).
/// - Dynamic limit copy strictly sourced from canonical AppLimitsConfig. Zero hardcoded limits.
/// - Action-Driven Navigation: Dropping or selecting a PDF immediately transitions to
///   the dedicated status/progress route (/annotate/process) where Ad #2 lives.
class PdfAnnotatePage extends StatefulWidget {
  final SelectedPdfFile? initialFile;

  const PdfAnnotatePage({super.key, this.initialFile});

  @override
  State<PdfAnnotatePage> createState() => _PdfAnnotatePageState();
}

class _PdfAnnotatePageState extends State<PdfAnnotatePage> {
  bool _isDragging = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    TelemetryService.trackPageView(
      '/annotate',
      pageTitle: 'FreePDFToolz — Annotate PDF',
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
        setState(() {});
      } else {
        setState(() {
          _errorMessage =
              'File "$name" (${(size / (1024 * 1024)).toStringAsFixed(1)} MB) exceeds the '
              '${AppLimitsConfig.activeLimitMb.toStringAsFixed(0)} MB limit. Watch an ad to boost your limit!';
        });
        break;
      }
    }
  }

  void _navigateToProcess(SelectedPdfFile file) {
    Navigator.of(context).pushNamed(
      '/annotate/process',
      arguments: {'file': file},
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const AppHeader(),
            const SizedBox(height: 24),

            // Top Ad Banner (Ad #1)
            const Center(
              child: AdSenseBanner(),
            ),
            const SizedBox(height: 32),

            // Title & Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    'Annotate PDF',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Highlight text, add notes, boxes, and markup directly on your PDF documents.',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Error banner if any
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withAlpha(75)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.red),
                      onPressed: () => setState(() => _errorMessage = null),
                    ),
                  ],
                ),
              ),

            // Dropzone Container
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: DropTarget(
                  onDragEntered: (detail) => setState(() => _isDragging = true),
                  onDragExited: (detail) => setState(() => _isDragging = false),
                  onDragDone: _handleDrop,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                    decoration: BoxDecoration(
                      color: isDark
                          ? (_isDragging ? const Color(0xFF1E293B) : const Color(0xFF1E293B).withAlpha(128))
                          : (_isDragging ? const Color(0xFFEFF6FF) : Colors.white),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isDragging
                            ? const Color(0xFFD97706)
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        width: 2,
                        style: BorderStyle.solid,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706).withAlpha(25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_note_rounded,
                            size: 36,
                            color: Color(0xFFD97706),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Drop PDF file here to annotate',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'or browse from your device',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.folder_open_rounded, size: 20),
                          label: const Text('Select PDF File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppLimitsConfig.dropzoneNoticeText,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),

            // Feature Highlights Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _buildFeatureCard(
                          icon: Icons.highlight_rounded,
                          title: 'Rich Markup Tools',
                          desc: 'Highlight, underline, strikeout text, draw boxes, and attach sticky notes.',
                          isDark: isDark,
                          width: isMobile ? double.infinity : (constraints.maxWidth - 16) / 2,
                        ),
                        _buildFeatureCard(
                          icon: Icons.palette_rounded,
                          title: 'Vibrant Colors',
                          desc: 'Customize markup colors with vivid, professional neon and standard color palettes.',
                          isDark: isDark,
                          width: isMobile ? double.infinity : (constraints.maxWidth - 16) / 2,
                        ),
                        _buildFeatureCard(
                          icon: Icons.lock_outline_rounded,
                          title: '100% Client & Memory Safe',
                          desc: 'Files are processed in volatile RAM and immediately wiped after conversion.',
                          isDark: isDark,
                          width: isMobile ? double.infinity : (constraints.maxWidth - 16) / 2,
                        ),
                        _buildFeatureCard(
                          icon: Icons.bolt_rounded,
                          title: 'Ultra-Fast WebP Previews',
                          desc: 'Smooth page navigation with instant compressed previews and zero double uploads.',
                          isDark: isDark,
                          width: isMobile ? double.infinity : (constraints.maxWidth - 16) / 2,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 48),

            // FAQ Accordion
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Frequently Asked Questions',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildFaqItem(
                      question: 'Are annotations compatible with Adobe Acrobat and other PDF readers?',
                      answer: 'Yes. FreePDFToolz uses standard ISO 32000 PDF annotations (Highlight, Underline, StrikeOut, Square, and Text). They are recognized natively by Adobe Acrobat, Apple Preview, Google Chrome, and standard PDF readers.',
                      isDark: isDark,
                    ),
                    _buildFaqItem(
                      question: 'Can I annotate multi-page PDFs?',
                      answer: 'Absolutely. You can navigate through all pages of your PDF document using the page switcher and apply distinct annotations to any page.',
                      isDark: isDark,
                    ),
                    _buildFaqItem(
                      question: 'Is FreePDFToolz really free?',
                      answer: 'Yes! FreePDFToolz is 100% free with no registration, no watermarks, and no software installations required.',
                      isDark: isDark,
                    ),
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

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String desc,
    required bool isDark,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 22, color: const Color(0xFFD97706)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqItem({
    required String question,
    required String answer,
    required bool isDark,
  }) {
    return ExpansionTile(
      title: Text(
        question,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Text(
          answer,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
