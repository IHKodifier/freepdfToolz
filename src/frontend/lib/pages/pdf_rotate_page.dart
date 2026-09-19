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

/// Tool Landing Page for Rotate PDF (/rotate)
///
/// Ad Monetization Architecture:
/// - Displays Tool Landing Ad (Ad #1).
/// - Dynamic limit copy strictly sourced from canonical AppLimitsConfig. Zero hardcoded limits.
/// - Action-Driven Navigation: Dropping or selecting a PDF immediately transitions to
///   the dedicated status/progress route (/rotate/process) where Ad #2 lives.
class PdfRotatePage extends StatefulWidget {
  final SelectedPdfFile? initialFile;

  const PdfRotatePage({super.key, this.initialFile});

  @override
  State<PdfRotatePage> createState() => _PdfRotatePageState();
}

class _PdfRotatePageState extends State<PdfRotatePage> {
  bool _isDragging = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    TelemetryService.trackPageView(
      '/rotate',
      pageTitle: 'FreePDFToolz — Rotate PDF',
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
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/rotate/process',
      arguments: {'file': file},
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      appBar: const AppHeader(currentRoute: '/rotate'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 960),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // AdSense Banner #1 (Landing Placement)
                    const AdSenseBanner(),
                    const SizedBox(height: 32),

                    // Tool Title & Subtitle
                    Text(
                      'Rotate PDF',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rotate individual pages or entire documents to 90, 180, or 270 degrees with instant visual preview.',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Apple-Grade Drag and Drop Target Zone
                    DropTarget(
                      onDragEntered: (_) => setState(() => _isDragging = true),
                      onDragExited: (_) => setState(() => _isDragging = false),
                      onDragDone: (details) {
                        setState(() => _isDragging = false);
                        _handleDrop(details);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 280),
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? const Color(0xFF0969DA).withOpacity(0.08)
                              : (isDark ? const Color(0xFF161B22) : Colors.white),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isDragging
                                ? const Color(0xFF0969DA)
                                : (isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1)),
                            width: _isDragging ? 2.5 : 1.5,
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
                            const SizedBox(height: 28),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0969DA).withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.rotate_right_rounded,
                                size: 48,
                                color: Color(0xFF0969DA),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Drop PDF file here',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'or click the button below to browse your device',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.folder_open_rounded, size: 20),
                              label: const Text(
                                'Select PDF File',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
                            const SizedBox(height: 20),
                            // Dynamic Limits Notice
                            Text(
                              AppLimitsConfig.dropzoneNoticeText,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Feature highlights / badges
                    Wrap(
                      spacing: 24,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildFeatureBadge(
                          icon: Icons.refresh_rounded,
                          title: 'Interactive Preview',
                          description: 'Rotate pages individually or all at once with live animated rotation.',
                          isDark: isDark,
                        ),
                        _buildFeatureBadge(
                          icon: Icons.verified_user_outlined,
                          title: '100% Private & Local',
                          description: 'Files process in secure RAM disk and are cleaned up immediately.',
                          isDark: isDark,
                        ),
                        _buildFeatureBadge(
                          icon: Icons.speed_rounded,
                          title: 'Instant Download',
                          description: 'High performance PyMuPDF engine applies changes losslessly in seconds.',
                          isDark: isDark,
                        ),
                      ],
                    ),
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

  Widget _buildFeatureBadge({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0969DA), size: 24),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
