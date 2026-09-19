import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/host_resolver.dart';
import '../utils/url_helper.dart';

/// Reusable Apple-inspired AppHeader with Navigation, Tools Switcher & Theme Toggle
/// Governed by docs/DESIGN.md & HostResolver (freeOCR.me vs FreePDFToolz)
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String currentRoute;
  final VoidCallback? onThemeToggle;
  final bool? showTools;

  const AppHeader({
    super.key,
    this.currentRoute = '/',
    this.onThemeToggle,
    this.showTools,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isPdfTools = HostResolver.isFreePdfToolsDomain();
    final showToolsDropdown = showTools ?? isPdfTools;
    final brandPrimary = isPdfTools ? 'FreePDF' : 'freeOCR';
    final brandSuffix = isPdfTools ? 'Toolz' : '.me';
    final homeRoute = HostResolver.getDefaultHomeRoute();

    final navTextStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );

    final activeNavStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.primary,
    );

    final headerContent = SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Row(
          children: [
            if (Navigator.canPop(context)) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
            ],
            // --- Brand Logo & Icon ---
            InkWell(
              onTap: () {
                if (currentRoute != homeRoute) {
                  Navigator.of(context).pushNamed(homeRoute);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPdfTools)
                    Container(
                      key: const Key('header_brand_logo'),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    )
                  else
                    ClipRRect(
                      key: const Key('header_brand_logo'),
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/images/brand_logo_icon.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.document_scanner_rounded,
                              color: Color(0xFF6366F1),
                              size: 20,
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(width: 8),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: theme.colorScheme.onSurface,
                        fontFamily: 'Inter',
                      ),
                      children: [
                        TextSpan(text: brandPrimary),
                        TextSpan(
                          text: brandSuffix,
                          style: const TextStyle(color: Color(0xFF6366F1)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // --- Desktop / Mobile Navigation Row ---
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = MediaQuery.of(context).size.width < 640;
                if (isMobile) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        icon: Icon(Icons.menu_rounded, color: theme.colorScheme.onSurface),
                        onSelected: (route) {
                          if (route == '/ocr') {
                            UrlHelper.openUrl('https://freeocr.me');
                          } else if (currentRoute != route) {
                            Navigator.of(context).pushNamed(route);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: homeRoute,
                            child: const Text('Home'),
                          ),
                          if (showToolsDropdown) ...[
                            const PopupMenuItem(
                              value: '/hub',
                              child: Text('All PDF Tools (16)'),
                            ),
                            const PopupMenuItem(
                              value: '/ocr',
                              child: Text('Free OCR'),
                            ),
                          ],
                          const PopupMenuItem(
                            value: '/kb',
                            child: Text('Knowledge Base'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      _buildThemeToggleButton(context, isDark),
                    ],
                  );
                }

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      key: const Key('header_home_btn'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        if (currentRoute != homeRoute) {
                          Navigator.of(context).pushNamed(homeRoute);
                        }
                      },
                      child: Text(
                        'Home',
                        style: (currentRoute == '/' || currentRoute == homeRoute)
                            ? activeNavStyle
                            : navTextStyle,
                      ),
                    ),
                    if (showToolsDropdown) ...[
                      const SizedBox(width: 4),
                      // --- Tools Dropdown Switcher ---
                      PopupMenuButton<String>(
                        key: const Key('header_tools_btn'),
                        tooltip: 'PDF Tools',
                        offset: const Offset(0, 36),
                        onSelected: (route) {
                          if (route == '/ocr') {
                            UrlHelper.openUrl('https://freeocr.me');
                          } else if (currentRoute != route) {
                            Navigator.of(context).pushNamed(route);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: '/hub',
                            child: Row(
                              children: [
                                Icon(Icons.dashboard_rounded, size: 18, color: Color(0xFF6366F1)),
                                SizedBox(width: 10),
                                Expanded(child: Text('All PDF Tools (16)')),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: '/merge',
                            child: Row(
                              children: [
                                Icon(Icons.call_merge_rounded, size: 18, color: Color(0xFF3B82F6)),
                                SizedBox(width: 10),
                                Expanded(child: Text('Merge PDF')),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: '/split',
                            child: Row(
                              children: [
                                Icon(Icons.call_split_rounded, size: 18, color: Color(0xFF3B82F6)),
                                SizedBox(width: 10),
                                Expanded(child: Text('Split PDF')),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: '/compress',
                            child: Row(
                              children: [
                                Icon(Icons.compress_rounded, size: 18, color: Color(0xFF10B981)),
                                SizedBox(width: 10),
                                Expanded(child: Text('Compress PDF')),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: '/ocr',
                            child: Row(
                              children: [
                                Icon(Icons.document_scanner_rounded, size: 18, color: Color(0xFF8B5CF6)),
                                SizedBox(width: 10),
                                Expanded(child: Text('OCR PDF')),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: '/pdf-to-word',
                            child: Row(
                              children: [
                                Icon(Icons.article_rounded, size: 18, color: Color(0xFF8B5CF6)),
                                SizedBox(width: 10),
                                Expanded(child: Text('Convert to Word')),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: '/summarize',
                            child: Row(
                              children: [
                                Icon(Icons.auto_stories_rounded, size: 18, color: Color(0xFF8B5CF6)),
                                SizedBox(width: 10),
                                Expanded(child: Text('Summarize PDF')),
                              ],
                            ),
                          ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Tools',
                                style: (currentRoute == '/hub' ||
                                        currentRoute.startsWith('/merge') ||
                                        currentRoute.startsWith('/split') ||
                                        currentRoute.startsWith('/compress'))
                                    ? activeNavStyle
                                    : navTextStyle,
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurface,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    TextButton(
                      key: const Key('header_kb_btn'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        if (currentRoute != '/kb') {
                          Navigator.of(context).pushNamed('/kb');
                        }
                      },
                      child: Text(
                        'Knowledge Base',
                        style: currentRoute.startsWith('/kb') ? activeNavStyle : navTextStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildThemeToggleButton(context, isDark),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? (kIsWeb ? const Color(0xFF0F172A) : const Color.fromRGBO(15, 23, 42, 0.85))
            : (kIsWeb ? const Color(0xFFF8FAFC) : const Color.fromRGBO(248, 250, 252, 0.85)),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.10)
                : const Color.fromRGBO(0, 0, 0, 0.08),
            width: 1.0,
          ),
        ),
      ),
      child: ClipRect(
        child: kIsWeb
            ? headerContent
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                child: headerContent,
              ),
      ),
    );
  }

  Widget _buildThemeToggleButton(BuildContext context, bool isDark) {
    return IconButton(
      key: const Key('header_theme_toggle_btn'),
      tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
      onPressed: onThemeToggle,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(8),
      style: IconButton.styleFrom(
        backgroundColor: isDark
            ? Colors.white.withOpacity(0.1)
            : const Color(0xFF6366F1).withOpacity(0.08),
      ),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) => RotationTransition(
          turns: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: Icon(
          isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
          key: ValueKey(isDark),
          color: isDark ? const Color(0xFFF59E0B) : const Color(0xFF6366F1),
          size: 18,
        ),
      ),
    );
  }
}
