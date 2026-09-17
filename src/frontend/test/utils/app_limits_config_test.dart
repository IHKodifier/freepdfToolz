import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/utils/app_limits_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLimitsConfig Unit Tests', () {
    setUp(() {
      AppLimitsConfig.resetBoost();
    });

    test('Initial defaults match canonical app_limits_config.json', () {
      expect(AppLimitsConfig.baseMaxFileMb, 100.0);
      expect(AppLimitsConfig.boostPerAdMb, 50.0);
      expect(AppLimitsConfig.maxStackFileMb, 1024.0);
      expect(AppLimitsConfig.adBoostTtlSeconds, 3600);
      expect(AppLimitsConfig.rewardedAdDurationSeconds, 15);
      expect(AppLimitsConfig.activeLimitMb, 100.0);
    });

    test('Evaluate correctly detects within-limit and exceeding files', () {
      // 50 MB is under 100 MB base limit
      final result50 = AppLimitsConfig.evaluate(50 * 1024 * 1024);
      expect(result50.isExceeded, isFalse);
      expect(result50.maxAllowedMb, 100.0);

      // 120 MB exceeds 100 MB base limit
      final result120 = AppLimitsConfig.evaluate(120 * 1024 * 1024);
      expect(result120.isExceeded, isTrue);
      expect(result120.maxAllowedMb, 100.0);
    });

    test('Calculate ads required calculates ceil of deficit / 50MB', () {
      // 120 MB with 100 MB limit -> deficit 20 MB -> 1 ad
      final ads120 = AppLimitsConfig.calculateAdsRequired(120 * 1024 * 1024);
      expect(ads120, 1);

      // 210 MB with 100 MB limit -> deficit 110 MB -> 3 ads (150MB boost)
      final ads210 = AppLimitsConfig.calculateAdsRequired(210 * 1024 * 1024);
      expect(ads210, 3);
    });

    test('Record boost updates active limit and respects maxStackFileMb', () {
      AppLimitsConfig.recordBoost(250.0);
      expect(AppLimitsConfig.activeLimitMb, 250.0);

      // Clamping to 1024 MB
      AppLimitsConfig.recordBoost(2000.0);
      expect(AppLimitsConfig.activeLimitMb, 1024.0);
    });

    test('Dynamic dropzone copy formats correctly without hardcoding', () {
      final copy = AppLimitsConfig.dropzoneNoticeText;
      expect(copy, contains('100MB free tier'));
      expect(copy, contains('1024MB'));
    });
  });
}
