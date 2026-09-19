import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/adsense_banner.dart';
import '../widgets/tool_card.dart';
import '../services/telemetry_service.dart';
import '../services/favorites_service.dart';
import '../utils/url_helper.dart';
import '../main.dart';

class ToolItemData {
  final String id;
  final String name;
  final String description;
  final String category;
  final String route;
  final IconData icon;
  final String? badge;
  final Color? color;

  const ToolItemData({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.route,
    required this.icon,
    this.badge,
    this.color,
  });
}

const List<ToolItemData> kPdfToolsCatalog = [
  // Page Operations (6 tools)
  ToolItemData(
    id: 'merge',
    name: 'Merge PDF',
    description: 'Combine multiple PDF files into a single unified document in any order.',
    category: 'page_ops',
    route: '/merge',
    icon: Icons.layers_rounded,
    badge: 'POPULAR',
    color: Color(0xFF4F46E5),
  ),
  ToolItemData(
    id: 'split',
    name: 'Split PDF',
    description: 'Extract individual pages or custom ranges into standalone PDF documents.',
    category: 'page_ops',
    route: '/split',
    icon: Icons.call_split_rounded,
    badge: 'POPULAR',
    color: Color(0xFF8B5CF6),
  ),
  ToolItemData(
    id: 'rotate',
    name: 'Rotate PDF',
    description: 'Rotate PDF pages clockwise or counter-clockwise permanently.',
    category: 'page_ops',
    route: '/rotate',
    icon: Icons.rotate_right_rounded,
    color: Color(0xFF0284C7),
  ),
  ToolItemData(
    id: 'delete-pages',
    name: 'Delete Pages',
    description: 'Remove unwanted, blank, or duplicate pages from your PDF file effortlessly.',
    category: 'page_ops',
    route: '/delete-pages',
    icon: Icons.delete_outline_rounded,
    color: Color(0xFFF43F5E),
  ),
  ToolItemData(
    id: 'extract-pages',
    name: 'Extract Pages',
    description: 'Select specific pages to extract into a fresh new PDF document.',
    category: 'page_ops',
    route: '/extract-pages',
    icon: Icons.file_copy_rounded,
    color: Color(0xFFF59E0B),
  ),
  ToolItemData(
    id: 'number-pages',
    name: 'Number Pages',
    description: 'Add clean, customizable page numbers to your PDF documents.',
    category: 'page_ops',
    route: '/number-pages',
    icon: Icons.format_list_numbered_rounded,
    badge: 'NEW',
    color: Color(0xFF10B981),
  ),

  // Security & Optimization (5 tools)
  ToolItemData(
    id: 'compress',
    name: 'Compress PDF',
    description: 'Reduce PDF file size while preserving high visual resolution and fidelity.',
    category: 'security',
    route: '/compress',
    icon: Icons.compress_rounded,
    badge: 'POPULAR',
    color: Color(0xFF0D9488),
  ),
  ToolItemData(
    id: 'watermark',
    name: 'Watermark PDF',
    description: 'Stamp custom text or transparent image watermarks across your document.',
    category: 'security',
    route: '/watermark',
    icon: Icons.branding_watermark_rounded,
    color: Color(0xFF0891B2),
  ),
  ToolItemData(
    id: 'crop',
    name: 'Crop PDF',
    description: 'Trim page margins or select custom viewport boundaries for your PDF.',
    category: 'security',
    route: '/crop',
    icon: Icons.crop_rounded,
    color: Color(0xFFEA580C),
  ),
  ToolItemData(
    id: 'redact',
    name: 'Redact PDF',
    description: 'Permanently black out sensitive text, data, and confidential areas.',
    category: 'security',
    route: '/redact',
    icon: Icons.visibility_off_rounded,
    badge: 'SECURITY',
    color: Color(0xFF64748B),
  ),
  ToolItemData(
    id: 'sign',
    name: 'Sign PDF',
    description: 'Draw, type, or upload verifiable digital signatures to sign PDF documents.',
    category: 'security',
    route: '/sign',
    icon: Icons.draw_rounded,
    badge: 'POPULAR',
    color: Color(0xFF7C3AED),
  ),

  // AI & Conversions (5 tools)
  ToolItemData(
    id: 'ocr',
    name: 'OCR PDF',
    description: 'Convert scanned PDFs and images into searchable PDFs and selectable text.',
    category: 'ai_conversions',
    route: '/ocr',
    icon: Icons.document_scanner_rounded,
    badge: 'AI',
    color: Color(0xFF2563EB),
  ),
  ToolItemData(
    id: 'annotate',
    name: 'Annotate PDF',
    description: 'Highlight text, add notes, boxes, and freehand markup directly on PDF.',
    category: 'ai_conversions',
    route: '/annotate',
    icon: Icons.edit_note_rounded,
    color: Color(0xFFD97706),
  ),
  ToolItemData(
    id: 'edit-text',
    name: 'Edit Text',
    description: 'Modify, correct, and update existing text inside PDF documents directly.',
    category: 'ai_conversions',
    route: '/edit-text',
    icon: Icons.text_fields_rounded,
    badge: 'NEW',
    color: Color(0xFF3B82F6),
  ),
  ToolItemData(
    id: 'pdf-to-word',
    name: 'Convert to Word',
    description: 'Convert PDF documents to editable Microsoft Word .docx format accurately.',
    category: 'ai_conversions',
    route: '/pdf-to-word',
    icon: Icons.description_rounded,
    badge: 'POPULAR',
    color: Color(0xFF1D4ED8),
  ),
  ToolItemData(
    id: 'summarize',
    name: 'Summarize PDF',
    description: 'Generate concise AI summaries, key takeaways, and outline briefs from long PDFs.',
    category: 'ai_conversions',
    route: '/summarize',
    icon: Icons.auto_awesome_rounded,
    badge: 'AI',
    color: Color(0xFFA855F7),
  ),
];

class PdfToolsHubPage extends StatefulWidget {
  const PdfToolsHubPage({super.key});

  @override
  State<PdfToolsHubPage> createState() => _PdfToolsHubPageState();
}

class _PdfToolsHubPageState extends State<PdfToolsHubPage> {
  String _searchQuery = '';
  String _selectedFilter = 'all'; // 'all' or 'favorites'
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    FavoritesService.init();
    TelemetryService.trackPageView('/pdf-tools', pageTitle: 'FreePDFToolz — All PDF Tools');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ToolItemData> _getFilteredTools(Set<String> favorites) {
    return kPdfToolsCatalog.where((tool) {
      final matchesFilter = _selectedFilter == 'all' || favorites.contains(tool.id);
      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          tool.name.toLowerCase().contains(query) ||
          tool.description.toLowerCase().contains(query);
      return matchesFilter && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SelectionArea(
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              pinned: false,
              elevation: 0,
              toolbarHeight: 64,
              expandedHeight: 64,
              backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              automaticallyImplyLeading: false,
              flexibleSpace: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 64,
                maxHeight: 64,
                child: AppHeader(
                  currentRoute: '/hub',
                  onThemeToggle: () {
                    if (isDark) {
                      themeNotifier.value = ThemeMode.light;
                    } else {
                      themeNotifier.value = ThemeMode.dark;
                    }
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AdSenseBanner(
                          height: 90.0,
                          margin: EdgeInsets.only(top: 8.0, bottom: 16.0),
                        ),
                        Center(child: _buildPill(isDark)),
                        const SizedBox(height: 16),
                        _buildHeroHeader(theme, isDark),
                        const SizedBox(height: 20),
                        _buildSearchBarAndFilters(theme, isDark),
                        const SizedBox(height: 24),
                        _buildToolsGrid(theme, isDark),
                        const SizedBox(height: 48),
                        _buildHowItWorksSection(theme, isDark),
                        const SizedBox(height: 36),
                        _buildZeroRetentionGuaranteeCard(theme, isDark),
                        const SizedBox(height: 36),
                        _buildEducationalFaqSection(theme, isDark),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 24.0),
                child: AppFooter(currentRoute: '/hub'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(ThemeData theme, bool isDark) {
    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: theme.colorScheme.onSurface,
              fontFamily: 'Inter',
              height: 1.2,
            ),
            children: const [
              TextSpan(text: 'Free, All-in-One '),
              TextSpan(
                text: 'PDF Tools Suite',
                style: TextStyle(color: Color(0xFF6366F1)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            'Free, fast, and completely private PDF Tools Suite. Process pages, edit documents, convert formats, and extract OCR without file retention.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPill(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x6610B981),
                  blurRadius: 3,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '16 Free Tools • 100% In-Memory • Zero File Retention',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4338CA),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBarAndFilters(ThemeData theme, bool isDark) {
    return Column(
      children: [
        // Search Input
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Search tools (e.g. merge, split, compress, ocr)...',
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark
                  ? const Color(0xFF1E293B).withOpacity(0.7)
                  : Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Simplified Filter Chips: All & Favorites
        ValueListenableBuilder<Set<String>>(
          valueListenable: FavoritesService.favoritesNotifier,
          builder: (context, favorites, _) {
            final favCount = favorites.length;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildFilterChip('all', 'All (${kPdfToolsCatalog.length})', theme),
                const SizedBox(width: 10),
                _buildFilterChip('favorites', '♥ Favorites ($favCount)', theme),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildFilterChip(String filterId, String label, ThemeData theme) {
    final isSelected = _selectedFilter == filterId;
    return FilterChip(
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? Colors.white : theme.colorScheme.onSurface,
        ),
      ),
      selectedColor: theme.colorScheme.primary,
      checkmarkColor: Colors.white,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withOpacity(0.12),
        ),
      ),
      onSelected: (selected) {
        setState(() {
          _selectedFilter = filterId;
        });
      },
    );
  }

  Widget _buildToolsGrid(ThemeData theme, bool isDark) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoritesService.favoritesNotifier,
      builder: (context, favorites, _) {
        final tools = _getFilteredTools(favorites);

        Widget content;
        if (_selectedFilter == 'favorites' && tools.isEmpty) {
          content = KeyedSubtree(
            key: const ValueKey('empty_favorites'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B).withOpacity(0.5) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    size: 48,
                    color: const Color(0xFFF43F5E).withOpacity(0.8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Favorite PDF Tools Yet',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      'Click the heart icon on any tool card to pin your most frequently used tools here for rapid 1-click access.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedFilter = 'all';
                      });
                    },
                    icon: const Icon(Icons.apps_rounded, size: 16),
                    label: const Text('Browse All 16 Tools'),
                  ),
                ],
              ),
            ),
          );
        } else if (tools.isEmpty) {
          content = KeyedSubtree(
            key: const ValueKey('empty_search'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No matching PDF tools found',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Try adjusting your search terms or clearing your search.',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _selectedFilter = 'all';
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reset Search'),
                  ),
                ],
              ),
            ),
          );
        } else {
          content = KeyedSubtree(
            key: ValueKey('grid_${_selectedFilter}_${tools.length}'),
            child: LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 1;
                if (constraints.maxWidth >= 1050) {
                  crossAxisCount = 4;
                } else if (constraints.maxWidth >= 760) {
                  crossAxisCount = 3;
                } else if (constraints.maxWidth >= 500) {
                  crossAxisCount = 2;
                }

                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 70,
                  ),
                  itemCount: tools.length,
                  itemBuilder: (context, index) {
                    final tool = tools[index];
                    return ToolCard(
                      key: ValueKey(tool.id),
                      id: tool.id,
                      name: tool.name,
                      description: tool.description,
                      category: tool.category,
                      route: tool.route,
                      icon: tool.icon,
                      badge: tool.badge,
                      color: tool.color,
                      onTap: tool.id == 'ocr'
                          ? () => UrlHelper.openUrl('https://freeocr.me')
                          : null,
                    );
                  },
                );
              },
            ),
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) {
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            );
          },
          child: content,
        );
      },
    );
  }

  Widget _buildHowItWorksSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
              ),
              child: const Text(
                'ARCHITECTURE & WORKFLOW',
                style: TextStyle(
                  color: Color(0xFF6366F1),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'How FreePDFToolz Operates Ephemerally',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Industrial-grade PDF document engineering running entirely in volatile Linux RAM disk mounts with zero persistent storage.',
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 780;
            final cards = [
              _buildWorkflowStep(
                step: '01',
                title: 'Select & Stage',
                description: 'Select your files or drag them into the dropzone. 100 MB free base upload limit, expandable up to 1 GB per file.',
                isDark: isDark,
                theme: theme,
              ),
              _buildWorkflowStep(
                step: '02',
                title: 'In-Memory Processing',
                description: 'Document streams route to volatile Linux tmpfs RAM disk. High-speed C/Rust engines merge, split, or optimize bytes in milliseconds.',
                isDark: isDark,
                theme: theme,
              ),
              _buildWorkflowStep(
                step: '03',
                title: 'Instant Download',
                description: 'Download the finalized document directly to your device, or request 24-hour expiring download links sent via email.',
                isDark: isDark,
                theme: theme,
              ),
              _buildWorkflowStep(
                step: '04',
                title: 'Instant Unlink & Purge',
                description: 'All memory buffers are immediately unlinked and returned to the OS kernel. No document or email is ever saved to disk.',
                isDark: isDark,
                theme: theme,
              ),
            ];

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cards.map((c) => Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: c,
                ))).toList(),
              );
            }
            return Column(
              children: cards.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: c,
              )).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWorkflowStep({
    required String step,
    required String title,
    required String description,
    required bool isDark,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withOpacity(0.6) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZeroRetentionGuaranteeCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0F172A), const Color(0xFF1E1B4B)]
              : [const Color(0xFFF8FAFC), const Color(0xFFEEF2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6366F1).withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: Color(0xFF10B981),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zero File & Zero Email Retention Policy',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Universal Privacy Guarantee Across freeOCR.me & FreePDFToolz',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Although you may share your email with us to receive download links in email, we never store, retain, or even cache your email addresses, making us in no position to bother you with unwanted marketing emails. Just like we have a zero retention policy for input and output files, we have a zero retention policy for your email addresses as well. That is why you do not need to sign up—our service is 100% free and privacy-focused.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '100% Volatile Linux tmpfs RAM disk • Zero hard drive retention • No marketing spam, ever.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEducationalFaqSection(ThemeData theme, bool isDark) {
    final faqs = [
      {
        'q': 'What is FreePDFToolz and how does it relate to freeOCR.me?',
        'a': 'FreePDFToolz is the comprehensive sister platform to freeOCR.me, extending its zero-retention ephemeral architecture to 16 essential PDF page manipulation, security, and conversion operations including Merge, Split, Rotate, Compress, and Sign.',
      },
      {
        'q': 'Are my uploaded PDF documents stored on your servers or analyzed for AI training?',
        'a': 'Never. Both FreePDFToolz and freeOCR.me operate under a strict Zero Persistent Storage Guarantee. Uploaded files, page vectors, and converted artifacts reside exclusively in volatile Linux RAM disk (tmpfs) mounts and are purged automatically immediately after processing.',
      },
      {
        'q': 'How does the free upload size limit work, and can I process large files over 100 MB?',
        'a': AdSenseBanner.kAdSenseApproved
            ? 'Every visitor receives an immediate 100 MB per-file upload allowance without registering or paying fees. For large archives, users can voluntarily view a 15-second sponsor video ad to boost their file limit by +50 MB, stackable all the way up to 1,024 MB (1 GB).'
            : 'Every visitor receives an immediate 100 MB per-file upload allowance without registering or paying fees. For large archives, users can request instant session limit passes to expand their file limit in +50 MB increments, stackable all the way up to 1,024 MB (1 GB).',
      },
      {
        'q': 'Will I receive marketing emails if I enter my email address on the results page?',
        'a': 'No. We never store, retain, or even cache email addresses provided for download link delivery. The address is used solely for the single dispatch transaction and never persisted in any database, making marketing contact technically impossible.',
      },
      {
        'q': 'How does FreePDFToolz Merge preserve font embeddings and vector quality?',
        'a': 'Our merge engine operates directly at the PDF cross-reference stream layer using PyMuPDF / MuPDF C bindings, preserving original vector curves, embedded fonts, annotations, and metadata bookmarks without rasterizing pages or degrading visual clarity.',
      },
      {
        'q': 'Is FreePDFToolz compliant with GDPR and CCPA privacy standards?',
        'a': 'Yes. Because we operate on a zero-registration, zero-account, and zero-file-retention architecture, we collect no personal data, sell no user information, and store no document files.',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.25)),
              ),
              child: Text(
                'FREQUENTLY ASKED QUESTIONS',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Everything You Need to Know About FreePDFToolz',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 16),
        ...faqs.map((faq) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: isDark ? const Color(0xFF1E293B).withOpacity(0.5) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                faq['q']!,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              iconColor: theme.colorScheme.primary,
              collapsedIconColor: theme.colorScheme.onSurfaceVariant,
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  faq['a']!,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        )),
      ],
    );
  }
}

