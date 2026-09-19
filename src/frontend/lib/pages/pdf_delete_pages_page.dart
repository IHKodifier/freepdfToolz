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

/// Tool Landing Page for Delete PDF Pages (/delete-pages)
///
/// Ad Monetization Architecture:
/// - Displays Tool Landing Ad (Ad #1).
/// - Dynamic limit copy strictly sourced from canonical AppLimitsConfig. Zero hardcoded limits.
/// - Action-Driven Navigation: Dropping or selecting a PDF immediately transitions to
///   the dedicated status/progress route (/delete-pages/process) where Ad #2 lives.
class PdfDeletePagesPage extends StatefulWidget {
  final SelectedPdfFile? initialFile;

  const PdfDeletePagesPage({super.key, this.initialFile});

  @override
  State<PdfDeletePagesPage> createState() => _PdfDeletePagesPageState();
}

class _PdfDeletePagesPageState extends State<PdfDeletePagesPage> {
  bool _isDragging = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    TelemetryService.trackPageView(
      '/delete-pages',
      pageTitle: 'FreePDFToolz — Delete Pages',
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
      '/delete-pages/process',
      arguments: {'file': file},
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      appBar: const AppHeader(currentRoute: '/delete-pages'),
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
                      'Delete PDF Pages',
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
                      'Remove unwanted, blank, or duplicate pages from your PDF file effortlessly with visual page selection.',
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
                      onDragDone: _handleDrop,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? (_isDragging ? const Color(0xFF1F242C) : const Color(0xFF161B22))
                              : (_isDragging ? const Color(0xFFF1F5F9) : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isDragging
                                ? const Color(0xFFCF222E)
                                : (isDark ? const Color(0xFF30363D) : const Color(0xFFE2E8F0)),
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
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFCF222E).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.delete_sweep_rounded,
                                size: 48,
                                color: Color(0xFFCF222E),
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
                              'Select a PDF file from your computer or cloud drive',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.folder_open_rounded),
                              label: const Text('Select PDF File'),
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
                            const SizedBox(height: 18),
                            // Dynamic Limits notice (no hardcoded limits)
                            Text(
                              AppLimitsConfig.dropzoneNoticeText,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Feature highlights
                    Wrap(
                      spacing: 24,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildFeaturePill(
                          icon: Icons.grid_view_rounded,
                          label: 'Visual Page Grid',
                          isDark: isDark,
                        ),
                        _buildFeaturePill(
                          icon: Icons.verified_user_outlined,
                          label: 'Client Privacy & Local RAM',
                          isDark: isDark,
                        ),
                        _buildFeaturePill(
                          icon: Icons.shield_outlined,
                          label: 'Guaranteed Page Retention',
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

  Widget _buildFeaturePill({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color: const Color(0xFFCF222E),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
