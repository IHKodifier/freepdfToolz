import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import 'semantic_pdf_icon.dart';

class ToolCard extends StatefulWidget {
  final String id;
  final String name;
  final String description;
  final String category;
  final String route;
  final IconData icon;
  final String? badge;
  final Color? color;
  final VoidCallback? onTap;

  const ToolCard({
    super.key,
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.route,
    required this.icon,
    this.badge,
    this.color,
    this.onTap,
  });

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final accentColor = widget.color ?? _getCategoryColor(widget.category, primaryColor);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            Navigator.of(context).pushNamed(widget.route);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: _isHovered
              ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 1.0))
              : Matrix4.identity(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? (_isHovered ? const Color(0xFF1E293B) : const Color(0xFF0F172A).withValues(alpha: 0.85))
                : (_isHovered ? Colors.white : Colors.white.withValues(alpha: 0.95)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered
                  ? accentColor.withValues(alpha: 0.50)
                  : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.07)),
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: accentColor.withValues(alpha: isDark ? 0.20 : 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Semantic Outline Vector Icon Container
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDark ? (_isHovered ? 0.25 : 0.16) : (_isHovered ? 0.16 : 0.08)),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: accentColor.withValues(alpha: isDark ? 0.35 : 0.20),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: SemanticPdfIcon(
                  toolId: widget.id,
                  color: accentColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              // Tool Name
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Optional Badge (POPULAR, AI, etc.)
              if (widget.badge != null) ...[
                const SizedBox(width: 6),
                _buildBadge(widget.badge!),
              ],
              const SizedBox(width: 4),
              // Heart / Favorite Toggle Button with Lively Spring & Ripple State-Change Animation
              ValueListenableBuilder<Set<String>>(
                valueListenable: FavoritesService.favoritesNotifier,
                builder: (context, favorites, _) {
                  final isFav = favorites.contains(widget.id);
                  return FavoriteHeartButton(
                    key: ValueKey('fav_btn_${widget.id}'),
                    isFav: isFav,
                    isDark: isDark,
                    onToggle: () {
                      FavoritesService.toggleFavorite(widget.id);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String badge) {
    Color bg;
    Color fg;

    switch (badge.toUpperCase()) {
      case 'POPULAR':
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
        fg = const Color(0xFFD97706);
        break;
      case 'AI':
        bg = const Color(0xFF8B5CF6).withValues(alpha: 0.15);
        fg = const Color(0xFF7C3AED);
        break;
      case 'SECURITY':
        bg = const Color(0xFF10B981).withValues(alpha: 0.15);
        fg = const Color(0xFF059669);
        break;
      case 'NEW':
      default:
        bg = const Color(0xFF06B6D4).withValues(alpha: 0.15);
        fg = const Color(0xFF0891B2);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        badge.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Color _getCategoryColor(String category, Color primaryColor) {
    switch (category) {
      case 'page_ops':
        return const Color(0xFF4F46E5);
      case 'security':
        return const Color(0xFF0D9488);
      case 'ai_conversions':
        return const Color(0xFF8B5CF6);
      default:
        return primaryColor;
    }
  }
}

/// Animated Favorite Heart Toggle with Spring Scale Pop and Unconstrained Visual Footprint
class FavoriteHeartButton extends StatefulWidget {
  final bool isFav;
  final VoidCallback onToggle;
  final bool isDark;

  const FavoriteHeartButton({
    super.key,
    required this.isFav,
    required this.onToggle,
    required this.isDark,
  });

  @override
  State<FavoriteHeartButton> createState() => _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends State<FavoriteHeartButton> {
  bool _isPopping = false;
  bool _isHovered = false;

  void _triggerPop() {
    if (mounted) {
      setState(() {
        _isPopping = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant FavoriteHeartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFav != oldWidget.isFav && !_isPopping) {
      _triggerPop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFav = widget.isFav;
    final inactiveColor = widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const activeColor = Color(0xFFF43F5E);

    return Tooltip(
      message: isFav ? 'Remove from favorites' : 'Add to favorites',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _triggerPop();
            widget.onToggle();
          },
          child: SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none, // Explicitly prevent parent clipping
              children: [
                // Background subtle hover/pop halo ring
                AnimatedContainer(
                  duration: Duration(milliseconds: _isPopping ? 450 : 300),
                  width: _isPopping ? 38 : 30,
                  height: _isPopping ? 38 : 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isPopping
                        ? activeColor.withValues(alpha: 0.22)
                        : (_isHovered
                            ? activeColor.withValues(alpha: isFav ? 0.16 : 0.08)
                            : Colors.transparent),
                  ),
                ),
                // Prominent Heart Icon: animates to 1.75x (31.5px) and onEnd springs back to 1.0x (900ms total)
                AnimatedScale(
                  scale: _isPopping ? 1.75 : (_isHovered ? 1.12 : 1.0),
                  duration: Duration(milliseconds: _isPopping ? 500 : 400),
                  curve: _isPopping ? Curves.easeOutBack : Curves.easeInOutCubic,
                  onEnd: () {
                    if (_isPopping && mounted) {
                      setState(() {
                        _isPopping = false;
                      });
                    }
                  },
                  child: SemanticHeartIcon(
                    isFilled: isFav,
                    size: 18,
                    color: isFav ? activeColor : inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pure vector heart icon that never fails due to font glyph or unicode tree-shaking issues in Web/CanvasKit/HTML.
class SemanticHeartIcon extends StatelessWidget {
  final bool isFilled;
  final Color color;
  final double size;

  const SemanticHeartIcon({
    super.key,
    required this.isFilled,
    required this.color,
    this.size = 15,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HeartPainter(isFilled: isFilled, color: color),
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  final bool isFilled;
  final Color color;

  const _HeartPainter({required this.isFilled, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Smooth, perfectly balanced bezier heart curve scaled to size
    final path = Path();
    path.moveTo(width * 0.5, height * 0.85);

    // Left lower arc to top left lobe
    path.cubicTo(
      width * 0.12, height * 0.58,
      0, height * 0.38,
      0, height * 0.24,
    );
    path.cubicTo(
      0, height * 0.08,
      width * 0.18, 0,
      width * 0.36, 0,
    );
    path.cubicTo(
      width * 0.44, 0,
      width * 0.48, height * 0.06,
      width * 0.5, height * 0.14,
    );

    // Right top lobe to lower point
    path.cubicTo(
      width * 0.52, height * 0.06,
      width * 0.56, 0,
      width * 0.64, 0,
    );
    path.cubicTo(
      width * 0.82, 0,
      width, height * 0.08,
      width, height * 0.24,
    );
    path.cubicTo(
      width, height * 0.38,
      width * 0.88, height * 0.58,
      width * 0.5, height * 0.85,
    );
    path.close();

    if (isFilled) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    } else {
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HeartPainter oldDelegate) {
    return oldDelegate.isFilled != isFilled || oldDelegate.color != color;
  }
}

/// Kept for backwards compatibility if referenced elsewhere.
class SemanticStarIcon extends SemanticHeartIcon {
  const SemanticStarIcon({
    super.key,
    required super.isFilled,
    required super.color,
    super.size = 18,
  });
}

