import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/telemetry_service.dart';
import 'services/host_resolver.dart';
import 'services/favorites_service.dart';
import 'widgets/hero_dropzone.dart';
import 'widgets/adsense_banner.dart';
import 'widgets/app_header.dart';
import 'widgets/app_footer.dart';
import 'widgets/landing_faq_section.dart';
import 'widgets/hero_scanner_showcase.dart';
import 'widgets/announcement_banner.dart';

import 'pages/process_page.dart';
import 'pages/result_page.dart';
import 'pages/kb_page.dart';
import 'pages/privacy_page.dart';
import 'pages/terms_page.dart';
import 'pages/about_page.dart';
import 'pages/contact_page.dart';
import 'pages/pdf_tools_hub_page.dart';
import 'pages/tool_placeholder_page.dart';
import 'pages/pdf_merge_page.dart';
import 'pages/pdf_merge_progress_page.dart';
import 'pages/pdf_split_page.dart';
import 'pages/pdf_split_progress_page.dart';
import 'pages/pdf_rotate_page.dart';
import 'pages/pdf_rotate_progress_page.dart';
import 'pages/pdf_delete_pages_page.dart';
import 'pages/pdf_delete_pages_progress_page.dart';
import 'pages/pdf_extract_pages_page.dart';
import 'pages/pdf_extract_pages_progress_page.dart';
import 'pages/pdf_number_pages_page.dart';
import 'pages/pdf_number_pages_progress_page.dart';
import 'pages/pdf_compress_page.dart';
import 'pages/pdf_compress_progress_page.dart';
import 'pages/pdf_watermark_page.dart';
import 'pages/pdf_watermark_progress_page.dart';
import 'pages/pdf_crop_page.dart';
import 'pages/pdf_crop_progress_page.dart';
import 'pages/pdf_redact_page.dart';
import 'pages/pdf_redact_progress_page.dart';
import 'pages/pdf_sign_page.dart';
import 'pages/pdf_sign_progress_page.dart';
import 'widgets/expired_link_view.dart';
import 'utils/url_strategy_helper.dart';
import 'utils/theme_storage_helper.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeStorageHelper.loadTheme());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppUrlStrategy();
  await FavoritesService.init();
  themeNotifier.addListener(() {
    ThemeStorageHelper.saveTheme(themeNotifier.value);
  });
  runApp(const FreeOcrApp());
}

class FreeOcrApp extends StatelessWidget {
  const FreeOcrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: HostResolver.getBrandTitle(),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          onGenerateRoute: (settings) {
            final name = settings.name;

            // FreePDFToolz Hub route
            if (name == '/hub' || name == '/pdf-tools') {
              return MaterialPageRoute(
                builder: (context) => const PdfToolsHubPage(),
                settings: settings,
              );
            }

            // Dedicated OCR route -> HomePage (with high-fidelity announcement & OCR dropzone)
            if (name == '/ocr') {
              return MaterialPageRoute(
                builder: (context) => const HomePage(),
                settings: settings,
              );
            }

            // Dedicated Merge PDF route (UC-017)
            if (name == '/merge') {
              return MaterialPageRoute(
                builder: (context) => const PdfMergePage(),
                settings: settings,
              );
            }

            // Dedicated Merge PDF Status & Progress route (UC-017)
            if (name == '/merge/process') {
              final args = settings.arguments;
              List<SelectedPdfFile> initialFiles = [];
              if (args is Map<String, dynamic> && args['files'] is List<SelectedPdfFile>) {
                initialFiles = args['files'] as List<SelectedPdfFile>;
              }
              return MaterialPageRoute(
                builder: (context) => PdfMergeProgressPage(initialFiles: initialFiles),
                settings: settings,
              );
            }

            // Dedicated Split PDF route (UC-018)
            if (name == '/split') {
              return MaterialPageRoute(
                builder: (context) => const PdfSplitPage(),
                settings: settings,
              );
            }

            // Dedicated Split PDF Status & Progress route (UC-018)
            if (name == '/split/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfSplitProgressPage(file: file),
                settings: settings,
              );
            }

            // Dedicated Rotate PDF route (UC-019)
            if (name == '/rotate') {
              return MaterialPageRoute(
                builder: (context) => const PdfRotatePage(),
                settings: settings,
              );
            }

            // Dedicated Rotate PDF Status & Progress route (UC-019)
            if (name == '/rotate/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfRotateProgressPage(file: file),
                settings: settings,
              );
            }

            // Dedicated Delete Pages route (UC-020)
            if (name == '/delete-pages') {
              return MaterialPageRoute(
                builder: (context) => const PdfDeletePagesPage(),
                settings: settings,
              );
            }

            // Dedicated Delete Pages Status & Progress route (UC-020)
            if (name == '/delete-pages/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfDeletePagesProgressPage(file: file),
                settings: settings,
              );
            }

            // Dedicated Extract Pages route (UC-021)
            if (name == '/extract-pages') {
              return MaterialPageRoute(
                builder: (context) => const PdfExtractPagesPage(),
                settings: settings,
              );
            }

            // Dedicated Extract Pages Status & Progress route (UC-021)
            if (name == '/extract-pages/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfExtractPagesProgressPage(file: file),
                settings: settings,
              );
            }

            // Dedicated Number Pages route (UC-022)
            if (name == '/number-pages') {
              return MaterialPageRoute(
                builder: (context) => const PdfNumberPagesPage(),
                settings: settings,
              );
            }

            // Dedicated Number Pages Status & Progress route (UC-022)
            if (name == '/number-pages/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfNumberPagesProgressPage(file: file),
                settings: settings,
              );
            }

            // Dedicated Compress PDF route (UC-023)
            if (name == '/compress') {
              return MaterialPageRoute(
                builder: (context) => const PdfCompressPage(),
                settings: settings,
              );
            }

            // Dedicated Compress PDF Status & Progress route (UC-023)
            if (name == '/compress/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfCompressProgressPage(file: file),
                settings: settings,
              );
            }

            // Dedicated Watermark PDF route (UC-024)
            if (name == '/watermark') {
              return MaterialPageRoute(
                builder: (context) => const PdfWatermarkPage(),
                settings: settings,
              );
            }

            // Dedicated Watermark PDF Status & Progress route (UC-024)
            if (name == '/watermark/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfWatermarkProgressPage(file: file),
                settings: settings,
              );
            }

            // Dedicated Crop PDF route (UC-025)
            if (name == '/crop') {
              return MaterialPageRoute(
                builder: (context) => const PdfCropPage(),
                settings: settings,
              );
            }

            // Dedicated Crop PDF Status & Progress route (UC-025)
            if (name == '/crop/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfCropProgressPage(file: file),
                settings: settings,
              );
            }

            // Dedicated Redact PDF route (UC-026)
            if (name == '/redact') {
              return MaterialPageRoute(
                builder: (context) => const PdfRedactPage(),
                settings: settings,
              );
            }

            // Dedicated Redact PDF Status & Progress route (UC-026)
            if (name == '/redact/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is SelectedPdfFile) {
                file = args;
              } else if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfRedactProgressPage(file: file),
                settings: settings,
              );
            }

            // Dedicated Sign PDF route (UC-027)
            if (name == '/sign') {
              return MaterialPageRoute(
                builder: (context) => const PdfSignPage(),
                settings: settings,
              );
            }

            // Dedicated Sign PDF Status & Progress route (UC-027)
            if (name == '/sign/process') {
              final args = settings.arguments;
              SelectedPdfFile? file;
              if (args is SelectedPdfFile) {
                file = args;
              } else if (args is Map<String, dynamic> && args['file'] is SelectedPdfFile) {
                file = args['file'] as SelectedPdfFile;
              }
              return MaterialPageRoute(
                builder: (context) => PdfSignProgressPage(file: file),
                settings: settings,
              );
            }

            // Specific PDF tools route matching
            if (name != null && name.startsWith('/')) {
              for (final tool in kPdfToolsCatalog) {
                if (tool.route == name && tool.id != 'ocr') {
                  return MaterialPageRoute(
                    builder: (context) => ToolPlaceholderPage(
                      toolId: tool.id,
                      toolTitle: tool.name,
                      description: tool.description,
                      icon: tool.icon,
                    ),
                    settings: settings,
                  );
                }
                if ('${tool.route}/process' == name && tool.id != 'ocr') {
                  return MaterialPageRoute(
                    builder: (context) => ToolPlaceholderPage(
                      toolId: '${tool.id}/process',
                      toolTitle: '${tool.name} (Processing)',
                      description: 'Processing ${tool.name} document workspace.',
                      icon: tool.icon,
                    ),
                    settings: settings,
                  );
                }
              }
            }

            if (name != null && (name == '/process' || name.startsWith('/process/'))) {
              final jobId = name.startsWith('/process/') ? name.replaceFirst('/process/', '') : null;
              final args = settings.arguments;
              String? filename;
              int? fileSize;
              Uint8List? bytes;
              String? layoutComplexity;
              bool coldStartActive = false;
              List<BatchFileItem>? batchItems;

              if (args is Map<String, dynamic>) {
                filename = args['filename'] as String?;
                fileSize = args['fileSize'] as int?;
                bytes = args['bytes'] as Uint8List?;
                layoutComplexity = args['layoutComplexity'] as String?;
                coldStartActive = args['coldStartActive'] as bool? ?? false;
                batchItems = args['batchItems'] as List<BatchFileItem>?;
              }

              return MaterialPageRoute(
                builder: (context) => ProcessPage(
                  jobId: jobId,
                  filename: filename,
                  fileSize: fileSize,
                  bytes: bytes,
                  layoutComplexity: layoutComplexity,
                  coldStartActive: coldStartActive,
                  batchItems: batchItems,
                ),
                settings: settings,
              );
            }
            if (name != null && name.startsWith('/result/')) {
              final jobId = name.replaceFirst('/result/', '');
              return MaterialPageRoute(
                builder: (context) => ResultPage(jobId: jobId),
                settings: settings,
              );
            }
            if (name != null && (name == '/expired' || name.startsWith('/expired'))) {
              return MaterialPageRoute(
                builder: (context) => Scaffold(
                  appBar: const AppHeader(currentRoute: '/expired'),
                  body: SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
                        child: Column(
                          children: [
                            const AdSenseBanner(),
                            const SizedBox(height: 16),
                            ExpiredLinkView(
                              expiredAt: DateTime.now().subtract(const Duration(hours: 24, minutes: 15)),
                              onUploadNew: () => Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  bottomNavigationBar: const AppFooter(currentRoute: '/expired'),
                ),
                settings: settings,
              );
            }
            if (name != null && (name == '/kb' || name == '/knowledge-base' || name.startsWith('/kb/') || name.startsWith('/knowledge-base/'))) {
              final slug = (name == '/kb' || name == '/knowledge-base')
                  ? null
                  : (name.startsWith('/kb/')
                      ? name.replaceFirst('/kb/', '')
                      : name.replaceFirst('/knowledge-base/', ''));
              return MaterialPageRoute(
                builder: (context) => KbPage(initialArticleSlug: slug),
                settings: settings,
              );
            }
            if (name == '/privacy') {
              return MaterialPageRoute(
                builder: (context) => const PrivacyPage(),
                settings: settings,
              );
            }
            if (name == '/terms') {
              return MaterialPageRoute(
                builder: (context) => const TermsPage(),
                settings: settings,
              );
            }
            if (name == '/about') {
              return MaterialPageRoute(
                builder: (context) => const AboutPage(),
                settings: settings,
              );
            }
            if (name == '/contact') {
              return MaterialPageRoute(
                builder: (context) => const ContactPage(),
                settings: settings,
              );
            }

            // Root route '/': FreePDFToolz 16-Tool Catalog Hub
            return MaterialPageRoute(
              builder: (context) => const PdfToolsHubPage(),
              settings: settings,
            );
          },
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showExpiredDevPreview = false;

  @override
  void initState() {
    super.initState();
    ApiService.prewarmBackend();
    TelemetryService.trackPageView('/', pageTitle: 'freeOCR.me — Home');
  }

  void _onUploadSuccess(String jobId, String filename, int sizeInBytes, {String? layoutComplexity, bool coldStartActive = false}) {
    Navigator.pushNamed(
      context,
      '/process/$jobId',
      arguments: {
        'filename': filename,
        'fileSize': sizeInBytes,
        'layoutComplexity': layoutComplexity,
        'coldStartActive': coldStartActive,
      },
    );
  }

  void _onBatchUploadSuccess(List<BatchFileItem> items) {
    if (items.isEmpty) return;
    final primaryJobId = items.first.jobId ?? 'batch';
    Navigator.pushNamed(
      context,
      '/process/$primaryJobId',
      arguments: {
        'batchItems': items,
        'filename': items.first.filename,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SelectionArea(
      child: Scaffold(
        resizeToAvoidBottomInset: false,
      floatingActionButton: kDebugMode
          ? FloatingActionButton.extended(
              key: const Key('dev_toggle_expired_fab'),
              onPressed: () {
                setState(() {
                  _showExpiredDevPreview = !_showExpiredDevPreview;
                });
              },
              icon: Icon(_showExpiredDevPreview ? Icons.timer_off : Icons.timer_outlined),
              label: Text(_showExpiredDevPreview ? 'Hide Expired UI' : 'Preview Expired UI'),
              backgroundColor: _showExpiredDevPreview ? Colors.redAccent : Colors.indigo,
              foregroundColor: Colors.white,
            )
          : null,
      appBar: AppHeader(
        currentRoute: '/',
        onThemeToggle: () {
          if (isDark) {
            themeNotifier.value = ThemeMode.light;
          } else {
            themeNotifier.value = ThemeMode.dark;
          }
        },
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (kDebugMode && _showExpiredDevPreview)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                child: ExpiredLinkView(
                  expiredAt: DateTime.now().subtract(const Duration(hours: 24, minutes: 30)),
                  onUploadNew: () => setState(() => _showExpiredDevPreview = false),
                ),
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isDesktop = constraints.maxWidth >= 992;
                    if (isDesktop) {
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AdSenseBanner(),
                            const SizedBox(height: 10),
                            const AnnouncementBanner(),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left Column (flex 7)
                                Expanded(
                                  flex: 7,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildPulseBadge(isDark),
                                      const SizedBox(height: 8),
                                      _buildHeadline(theme, textAlign: TextAlign.left),
                                      const SizedBox(height: 6),
                                      _buildSubtitle(theme, textAlign: TextAlign.left),
                                      const SizedBox(height: 12),
                                      HeroDropzone(
                                        onUploadSuccess: _onUploadSuccess,
                                        onBatchUploadSuccess: _onBatchUploadSuccess,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 28),
                                // Right Column (flex 5)
                                const Expanded(
                                  flex: 5,
                                  child: HeroScannerShowcase(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    } else {
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const AdSenseBanner(),
                            const SizedBox(height: 10),
                            const AnnouncementBanner(),
                            const SizedBox(height: 12),
                            _buildPulseBadge(isDark),
                            const SizedBox(height: 8),
                            _buildHeadline(theme, textAlign: TextAlign.center, fontSize: 32),
                            const SizedBox(height: 6),
                            _buildSubtitle(theme, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            HeroDropzone(
                              onUploadSuccess: _onUploadSuccess,
                              onBatchUploadSuccess: _onBatchUploadSuccess,
                            ),
                            const SizedBox(height: 20),
                            const HeroScannerShowcase(),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            const LandingFaqSection(),
            const SizedBox(height: 32),
            const AppFooter(),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildPulseBadge(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6366F1).withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x6610B981),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '100% Free • Zero File Retention • No Registration',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4338CA),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadline(ThemeData theme, {TextAlign textAlign = TextAlign.left, double fontSize = 40}) {
    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.0,
          color: theme.colorScheme.onSurface,
          fontFamily: 'Inter',
          height: 1.15,
        ),
        children: const [
          TextSpan(text: 'Extract Text with '),
          TextSpan(
            text: 'Precision',
            style: TextStyle(color: Color(0xFF6366F1)),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitle(ThemeData theme, {TextAlign textAlign = TextAlign.left}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Text(
        'Secure, fast, and highly accurate optical character recognition powered by advanced neural engines. Files are processed in memory and never stored.',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
        textAlign: textAlign,
      ),
    );
  }
}
