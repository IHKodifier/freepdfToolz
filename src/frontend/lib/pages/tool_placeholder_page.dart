import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/adsense_banner.dart';
import '../services/telemetry_service.dart';
import '../utils/app_limits_config.dart';
import '../main.dart';

class ToolPlaceholderPage extends StatefulWidget {
  final String toolId;
  final String toolTitle;
  final String description;
  final IconData icon;

  const ToolPlaceholderPage({
    super.key,
    required this.toolId,
    required this.toolTitle,
    required this.description,
    required this.icon,
  });

  @override
  State<ToolPlaceholderPage> createState() => _ToolPlaceholderPageState();
}

class _ToolPlaceholderPageState extends State<ToolPlaceholderPage> {
  bool _isDragging = false;

  void _showComingSoonDialog(BuildContext context, [String? filename]) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(widget.icon, color: const Color(0xFF6366F1), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${widget.toolTitle} • Sprint F3',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'SPRINT F3 • UNDER ACTIVE DEVELOPMENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6366F1),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (filename != null) ...[
              Text(
                'Selected: $filename',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'The ${widget.toolTitle} tool is currently in development as part of Sprint F3. '
              'In the meantime, 12 production-ready tools (Rotate, Delete Pages, Extract Pages, Merge, Split, Compress, Crop, Redact, Sign, Watermark, Number Pages, Protect) are fully active and available now.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? const Color(0xFF8B949E) : const Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushNamed('/hub');
            },
            icon: const Icon(Icons.grid_view_rounded, size: 16),
            label: const Text('Explore Active Tools'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (res != null && res.files.isNotEmpty) {
        if (mounted) {
          _showComingSoonDialog(context, res.files.first.name);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    TelemetryService.trackPageView('/${widget.toolId}', pageTitle: 'FreePDFToolz — ${widget.toolTitle}');
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SelectionArea(
      child: Scaffold(
        appBar: AppHeader(
          currentRoute: '/${widget.toolId}',
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
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // AdSense Banner
                        const AdSenseBanner(),
                        const SizedBox(height: 24),

                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withOpacity(0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(widget.icon, color: Colors.white, size: 32),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.toolTitle,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF6366F1).withOpacity(0.3),
                                ),
                              ),
                              child: const Text(
                                'SPRINT F3',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Interactive Dropzone + File Picker
                        DropTarget(
                          onDragEntered: (_) => setState(() => _isDragging = true),
                          onDragExited: (_) => setState(() => _isDragging = false),
                          onDragDone: (details) {
                            setState(() => _isDragging = false);
                            final pdfs = details.files.where((f) => f.name.toLowerCase().endsWith('.pdf')).toList();
                            if (pdfs.isNotEmpty) {
                              _showComingSoonDialog(context, pdfs.first.name);
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
                            decoration: BoxDecoration(
                              color: _isDragging
                                  ? const Color(0xFF6366F1).withOpacity(0.08)
                                  : (isDark ? const Color(0xFF1E293B) : Colors.white),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _isDragging
                                    ? const Color(0xFF6366F1)
                                    : (isDark ? const Color(0xFF30363D) : const Color(0xFFCBD5E1)),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 48,
                                  color: const Color(0xFF6366F1),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Drop PDF files here or browse to upload',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Max file size: ${AppLimitsConfig.baseLimitFormatted} free • Processed securely in RAM disk',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                     ElevatedButton.icon(
                                       key: const Key('placeholder_select_btn'),
                                       onPressed: _pickFile,
                                       icon: const Icon(Icons.file_open_rounded, size: 18),
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
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).pushNamed('/hub');
                                      },
                                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                                      label: const Text('Back to PDF Tools Hub'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 64),
              AppFooter(currentRoute: '/${widget.toolId}'),
            ],
          ),
        ),
      ),
    );
  }
}
