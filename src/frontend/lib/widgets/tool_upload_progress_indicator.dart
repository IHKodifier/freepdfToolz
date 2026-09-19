import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api_service.dart' show formatBytes;

/// Modern, glassmorphic progress card displayed during PDF Suite tool uploads.
/// Reflects true network socket byte transfer polled every 600 milliseconds,
/// featuring an active animated light shimmer over the progress bar to prevent
/// frozen perception during TCP buffer flushes, then automatically transitions
/// to document processing once 100% is transferred.
class ToolUploadProgressIndicator extends StatefulWidget {
  final int sentBytes;
  final int totalBytes;
  final bool isUploading;
  final String processingLabel;
  final Color? accentColor;

  const ToolUploadProgressIndicator({
    super.key,
    required this.sentBytes,
    required this.totalBytes,
    required this.isUploading,
    this.processingLabel = 'Processing Document...',
    this.accentColor,
  });

  @override
  State<ToolUploadProgressIndicator> createState() => _ToolUploadProgressIndicatorState();
}

class _ToolUploadProgressIndicatorState extends State<ToolUploadProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = widget.accentColor ?? theme.colorScheme.primary;

    final effectiveTotal = widget.totalBytes > 0 ? widget.totalBytes : 1;
    final progress = (widget.sentBytes / effectiveTotal).clamp(0.0, 1.0);
    final percent = (progress * 100).toInt();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryColor.withValues(alpha: isDark ? 0.35 : 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _shimmerController,
                builder: (context, child) {
                  final pulse = widget.isUploading
                      ? 0.10 + 0.08 * (0.5 + 0.5 * math.sin(_shimmerController.value * 2 * math.pi))
                      : 0.12;
                  return Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: pulse),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(
                        widget.isUploading ? Icons.cloud_upload_rounded : Icons.auto_awesome_rounded,
                        color: primaryColor,
                        size: 20,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isUploading ? 'Uploading Document...' : widget.processingLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.isUploading
                          ? '${formatBytes(widget.sentBytes)} of ${formatBytes(widget.totalBytes)} transferred'
                          : 'Transforming document securely in RAM disk...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isUploading)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$percent%',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Shimmer-enhanced linear progress track
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              width: double.infinity,
              child: widget.isUploading
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final totalWidth = constraints.maxWidth;
                        final fillWidth = (totalWidth * progress).clamp(0.0, totalWidth);
                        return Stack(
                          children: [
                            // Base track background
                            Container(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                            ),
                            // Active filled progress with contained shimmer
                            SizedBox(
                              width: fillWidth,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Stack(
                                  children: [
                                    Container(color: primaryColor),
                                    AnimatedBuilder(
                                      animation: _shimmerController,
                                      builder: (context, child) {
                                        final animVal = _shimmerController.value;
                                        return Positioned(
                                          left: -80 + ((fillWidth + 80) * animVal),
                                          top: 0,
                                          bottom: 0,
                                          width: 80,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.white.withValues(alpha: 0.0),
                                                  Colors.white.withValues(alpha: 0.55),
                                                  Colors.white.withValues(alpha: 0.0),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  : LinearProgressIndicator(
                      minHeight: 8,
                      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (!widget.isUploading)
                Text(
                  'Server execution underway',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                const SizedBox.shrink(),
              if (widget.isUploading)
                Text(
                  '${formatBytes(widget.sentBytes)} / ${formatBytes(widget.totalBytes)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
