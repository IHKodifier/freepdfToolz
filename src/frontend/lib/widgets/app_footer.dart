import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../constants/social_links.dart';
import '../utils/url_helper.dart';
import '../services/host_resolver.dart';
import 'brand_icons.dart';

/// Global, responsive 4-column footer component for freeOCR.me & FreePDFToolz.me.
/// Governed by docs/DESIGN.md, HostResolver, and brand route context.
class AppFooter extends StatelessWidget {
  final String? currentRoute;

  const AppFooter({super.key, this.currentRoute});


  void _navigateTo(BuildContext context, String routeName) {
    if (ModalRoute.of(context)?.settings.name != routeName) {
      Navigator.pushNamed(context, routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final sectionTitleStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: colorScheme.onSurface,
      fontFamily: 'Inter',
    );

    final linkStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurfaceVariant,
      fontFamily: 'Inter',
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? const Color.fromRGBO(15, 23, 42, 0.90)
            : const Color(0xFFF1F5F9),
        border: Border(
          top: BorderSide(
            color: isDark
                ? const Color.fromRGBO(255, 255, 255, 0.10)
                : const Color.fromRGBO(0, 0, 0, 0.08),
            width: 1.0,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1140),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 700;

              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBrandColumn(context, theme, colorScheme, linkStyle),
                    const SizedBox(height: 32),
                    _buildNavColumn(context, sectionTitleStyle, linkStyle),
                    const SizedBox(height: 32),
                    _buildEnginesColumn(
                      context,
                      theme,
                      colorScheme,
                      sectionTitleStyle,
                    ),
                    const SizedBox(height: 32),
                    _buildLegalColumn(context, sectionTitleStyle, linkStyle),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildBrandColumn(
                      context,
                      theme,
                      colorScheme,
                      linkStyle,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: _buildNavColumn(
                      context,
                      sectionTitleStyle,
                      linkStyle,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: _buildEnginesColumn(
                      context,
                      theme,
                      colorScheme,
                      sectionTitleStyle,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: _buildLegalColumn(
                      context,
                      sectionTitleStyle,
                      linkStyle,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  bool _isPdfTools(BuildContext context) {
    if (HostResolver.isFreePdfToolsDomain()) return true;
    final route = currentRoute ?? ModalRoute.of(context)?.settings.name;
    if (route != null) {
      if (route == '/hub' ||
          route.startsWith('/merge') ||
          route.startsWith('/split') ||
          route.startsWith('/rotate') ||
          route.startsWith('/delete-pages') ||
          route.startsWith('/extract-pages') ||
          route.startsWith('/number-pages') ||
          route.startsWith('/tools')) {
        return true;
      }
    }
    return false;
  }

  // --- Column 1: Brand & Social Handles ---
  Widget _buildBrandColumn(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    TextStyle linkStyle,
  ) {
    final isPdfTools = _isPdfTools(context);
    final brandTitle = isPdfTools ? 'FreePDFToolz' : 'freeOCR.me';
    final brandSubtitle = isPdfTools
        ? '© 2026 FreePDFToolz.me • 100% Free & Local-First PDF Platform.\nAll rights reserved. Zero retention & RAM disk privacy.'
        : '© 2026 freeOCR.me • Privacy-First Ephemeral OCR Platform.\nAll rights reserved. Files processed in RAM disk.';
    final brandIcon = isPdfTools
        ? Icons.picture_as_pdf_rounded
        : Icons.document_scanner_rounded;
    final brandColor = isPdfTools
        ? const Color(0xFFEF4444)
        : const Color(0xFF6366F1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: brandColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  brandIcon,
                  color: brandColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                brandTitle,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: colorScheme.onSurface,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          brandSubtitle,
          style: linkStyle.copyWith(fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            IconButton(
              key: const Key('footer_social_twitter'),
              icon: BrandIcon(
                type: BrandType.xTwitter,
                size: 20,
                color: colorScheme.onSurface,
              ),
              tooltip: 'Twitter / X',
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(36, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => SocialLinks.openSocialChannel(
                context,
                platformName: 'Twitter / X',
                url: SocialLinks.twitterUrl,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('footer_social_instagram'),
              icon: BrandIcon(
                type: BrandType.instagram,
                size: 20,
                color: colorScheme.onSurface,
              ),
              tooltip: 'Instagram',
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(36, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => SocialLinks.openSocialChannel(
                context,
                platformName: 'Instagram',
                url: SocialLinks.instagramUrl,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('footer_social_facebook'),
              icon: BrandIcon(
                type: BrandType.facebook,
                size: 20,
                color: colorScheme.onSurface,
              ),
              tooltip: 'Facebook',
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(36, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => SocialLinks.openSocialChannel(
                context,
                platformName: 'Facebook',
                url: SocialLinks.facebookUrl,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Column 2: Navigation Links ---
  Widget _buildNavColumn(
    BuildContext context,
    TextStyle titleStyle,
    TextStyle linkStyle,
  ) {
    final isPdfTools = _isPdfTools(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Navigation', style: titleStyle),
        const SizedBox(height: 14),
        InkWell(
          key: const Key('footer_home_btn'),
          onTap: () => _navigateTo(context, isPdfTools ? '/hub' : '/'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(isPdfTools ? 'Tools Hub' : 'Home', style: linkStyle),
          ),
        ),
        if (isPdfTools)
          InkWell(
            key: const Key('footer_ocr_btn'),
            onTap: () => UrlHelper.openUrl('https://freeocr.me'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Text('OCR PDF', style: linkStyle),
            ),
          ),
        InkWell(
          key: const Key('footer_about_btn'),
          onTap: () => _navigateTo(context, '/about'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text('About Us', style: linkStyle),
          ),
        ),
        InkWell(
          key: const Key('footer_kb_btn'),
          onTap: () => _navigateTo(context, '/kb'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text('Knowledge Base', style: linkStyle),
          ),
        ),
        InkWell(
          key: const Key('footer_ai_ocr_btn'),
          onTap: () => _navigateTo(context, '/kb/ai-vs-traditional-ocr'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text('AI vs Traditional OCR', style: linkStyle),
          ),
        ),
      ],
    );
  }


  // --- Column 3: Open-Source Engine Attributions ---
  Widget _buildEnginesColumn(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    TextStyle titleStyle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Engines', style: titleStyle),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildEngineChip(
              context,
              label: "Baidu Unlimited OCR",
              url: SocialLinks.baiduOcrUrl,
              key: const Key('chip_baiduocr'),
            ),
            _buildEngineChip(
              context,
              label: 'Tesseract OCR',
              url: SocialLinks.tesseractUrl,
              key: const Key('chip_tesseract'),
            ),
            _buildEngineChip(
              context,
              label: 'OCRmyPDF',
              url: SocialLinks.ocrmypdfUrl,
              key: const Key('chip_ocrmypdf'),
            ),
            _buildEngineChip(
              context,
              label: 'PyMuPDF',
              url: SocialLinks.pymupdfUrl,
              key: const Key('chip_pymupdf'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEngineChip(
    BuildContext context, {
    required String label,
    required String url,
    required Key key,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ActionChip(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
      onPressed: () => UrlHelper.openUrl(url),
      backgroundColor: isDark
          ? Colors.white.withOpacity(0.06)
          : colorScheme.surfaceContainer,
      side: BorderSide(
        color: isDark
            ? Colors.white.withOpacity(0.12)
            : const Color(0xFFCBD5E1),
        width: 0.8,
      ),
    );
  }

  // --- Column 4: Legal & Policy Links ---
  Widget _buildLegalColumn(
    BuildContext context,
    TextStyle titleStyle,
    TextStyle linkStyle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Legal', style: titleStyle),
        const SizedBox(height: 14),
        InkWell(
          key: const Key('footer_privacy_btn'),
          onTap: () => _navigateTo(context, '/privacy'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text('Privacy Policy', style: linkStyle),
          ),
        ),
        InkWell(
          key: const Key('footer_terms_btn'),
          onTap: () => _navigateTo(context, '/terms'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text('Terms of Service', style: linkStyle),
          ),
        ),
        InkWell(
          key: const Key('footer_contact_btn'),
          onTap: () => _navigateTo(context, '/contact'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text('Contact Us', style: linkStyle),
          ),
        ),
        InkWell(
          key: const Key('footer_source_code_btn'),
          onTap: () => UrlHelper.openUrl(SocialLinks.githubRepoUrl),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text('Source Code (GitHub)', style: linkStyle),
          ),
        ),
      ],
    );
  }
}
