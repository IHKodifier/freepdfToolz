import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'limit_evaluator.dart';

/// Canonical Single Source of Truth for Application Limits & Monetization Rules.
/// Sourced dynamically from `src/backend/app/app_limits_config.json` via:
/// 1. Live backend endpoint `GET /api/v1/config`
/// 2. Bundled fallback asset `assets/config/app_limits_config.json`
///
/// Both FreeOCR.me and FreePDFToolz share this exact canonical configuration.
class AppLimitsConfig {
  static double baseMaxFileMb = 100.0;
  static double boostPerAdMb = 50.0;
  static double maxStackFileMb = 1024.0;
  static int adBoostTtlSeconds = 3600;
  static int rewardedAdDurationSeconds = 15;
  static bool displayAdsEnabled = true;
  static bool rewardedAdsEnabled = true;

  // Global session-level active boost tracking
  static double _activeLimitMb = 100.0;
  static DateTime? _boostExpiresAt;
  static bool _isLoaded = false;

  /// Loads canonical limits from runtime configuration.
  static Future<void> ensureLoaded() async {
    try {
      final config = await ApiService.fetchRuntimeConfig();
      final limits = config['limits'] as Map<String, dynamic>? ?? {};
      final monetization = config['monetization'] as Map<String, dynamic>? ?? {};

      baseMaxFileMb = (limits['base_max_file_mb'] as num?)?.toDouble() ?? 100.0;
      boostPerAdMb = (limits['boost_per_ad_mb'] as num?)?.toDouble() ?? 50.0;
      maxStackFileMb = (limits['max_stack_file_mb'] as num?)?.toDouble() ?? 1024.0;
      adBoostTtlSeconds = (limits['ad_boost_ttl_seconds'] as num?)?.toInt() ?? 3600;
      rewardedAdDurationSeconds = (monetization['rewarded_ad_duration_seconds'] as num?)?.toInt() ?? 15;
      displayAdsEnabled = monetization['display_ads_enabled'] as bool? ?? true;
      rewardedAdsEnabled = monetization['rewarded_ads_enabled'] as bool? ?? true;

      if (_activeLimitMb < baseMaxFileMb) {
        _activeLimitMb = baseMaxFileMb;
      }
      _isLoaded = true;
    } catch (e) {
      debugPrint('[AppLimitsConfig] Error loading config: $e');
    }
  }

  /// Whether config has already been loaded.
  static bool get isLoaded => _isLoaded;

  /// Returns currently active limit in MB, accounting for session boost TTL.
  static double get activeLimitMb {
    if (_boostExpiresAt != null && DateTime.now().isBefore(_boostExpiresAt!)) {
      return _activeLimitMb.clamp(baseMaxFileMb, maxStackFileMb);
    }
    return baseMaxFileMb;
  }

  /// Records a successful rewarded video ad watch, boosting active session limit.
  static void recordBoost(double newLimitMb) {
    _activeLimitMb = newLimitMb > maxStackFileMb ? maxStackFileMb : newLimitMb;
    _boostExpiresAt = DateTime.now().add(Duration(seconds: adBoostTtlSeconds));
    ApiService.notifyRewardedAdWatched();
  }

  /// Resets active session boost to base tier.
  static void resetBoost() {
    _activeLimitMb = baseMaxFileMb;
    _boostExpiresAt = null;
  }

  /// Evaluates whether a file size in bytes exceeds the current active limit.
  static LimitEvaluationResult evaluate(int fileSizeInBytes) {
    return LimitEvaluator.evaluate(
      fileSizeInBytes: fileSizeInBytes,
      currentLimitMb: activeLimitMb,
    );
  }

  /// Calculates how many rewarded video ads are needed for a given file size.
  static int calculateAdsRequired(int fileSizeInBytes) {
    return LimitEvaluator.calculateAdsRequired(
      fileSizeInBytes: fileSizeInBytes,
      currentLimitMb: activeLimitMb,
      boostPerAdMb: boostPerAdMb,
    );
  }

  /// Formatted dynamic notice string for dropzones across all tools.
  static String get dropzoneNoticeText {
    return 'Max ${baseMaxFileMb.toInt()}MB free tier • Boost up to ${maxStackFileMb.toInt()}MB with rewarded ads';
  }

  /// Formatted dynamic base limit string (e.g. "100 MB").
  static String get baseLimitFormatted {
    return '${baseMaxFileMb.toInt()} MB';
  }
}
