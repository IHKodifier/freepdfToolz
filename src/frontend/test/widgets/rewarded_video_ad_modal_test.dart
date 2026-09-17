import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/widgets/rewarded_video_ad_modal.dart';
import 'package:freepdftoolz_frontend/utils/limit_evaluator.dart';

void main() {
  group('LimitEvaluator Unit Tests', () {
    test('Correctly identifies file size under limit', () {
      const fileSizeInBytes = 25 * 1024 * 1024; // 25MB
      const currentLimitMb = 50.0;
      final result = LimitEvaluator.evaluate(
        fileSizeInBytes: fileSizeInBytes,
        currentLimitMb: currentLimitMb,
      );
      expect(result.isExceeded, isFalse);
      expect(result.fileSizeMb, closeTo(25.0, 0.01));
    });

    test(
      'Correctly calculates ads required for single and multi-boost payloads',
      () {
        // Under limit -> 0 ads
        expect(
          LimitEvaluator.calculateAdsRequired(
            fileSizeInBytes: 25 * 1024 * 1024,
            currentLimitMb: 50.0,
          ),
          equals(0),
        );

        // 60 MB on 50 MB limit -> 1 ad
        expect(
          LimitEvaluator.calculateAdsRequired(
            fileSizeInBytes: 60 * 1024 * 1024,
            currentLimitMb: 50.0,
          ),
          equals(1),
        );

        // 105 MB on 100 MB limit -> 1 ad
        expect(
          LimitEvaluator.calculateAdsRequired(
            fileSizeInBytes: 105 * 1024 * 1024,
            currentLimitMb: 100.0,
          ),
          equals(1),
        );

        // 170 MB on 100 MB limit -> 2 ads
        expect(
          LimitEvaluator.calculateAdsRequired(
            fileSizeInBytes: 170 * 1024 * 1024,
            currentLimitMb: 100.0,
          ),
          equals(2),
        );

        // 250 MB on 100 MB limit -> 3 ads
        expect(
          LimitEvaluator.calculateAdsRequired(
            fileSizeInBytes: 250 * 1024 * 1024,
            currentLimitMb: 100.0,
          ),
          equals(3),
        );
      },
    );
  });

  group('RewardedVideoAdModal Widget Tests', () {
    setUp(() {
      RewardedVideoAdModal.debugOverrideAdPlayback = true;
    });

    tearDown(() {
      RewardedVideoAdModal.debugOverrideAdPlayback = null;
    });

    testWidgets(
      'Renders frosted glass modal with file size and boost options',
      (WidgetTester tester) async {
        bool watchAdClicked = false;
        bool cancelClicked = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RewardedVideoAdModal(
                filename: 'large_document.pdf',
                fileSizeInBytes: 60 * 1024 * 1024,
                currentLimitMb: 50.0,
                boostPerAdMb: 50.0,
                maxStackMb: 1024.0,
                adDurationSeconds: 15,
                onWatchAd: (boostedLimit) {
                  watchAdClicked = true;
                },
                onCancel: () {
                  cancelClicked = true;
                },
              ),
            ),
          ),
        );

        // Verify Title & Filename
        expect(find.text('File Size Limit Exceeded'), findsOneWidget);
        expect(find.textContaining('large_document.pdf'), findsOneWidget);

        // Verify initial callback states
        expect(watchAdClicked, isFalse);
        expect(cancelClicked, isFalse);

        // Verify file size and limit display
        expect(find.textContaining('60.0 MB'), findsOneWidget);
        expect(find.textContaining('50.0 MB'), findsOneWidget);

        // Verify boost pass info (+50 MB per ad up to 1024 MB)
        expect(find.textContaining('+50 MB'), findsWidgets);
        expect(find.textContaining('1024 MB'), findsOneWidget);

        // Verify Watch Ad button
        final watchAdButton = find.textContaining(
          'Watch 15s Ad to Stack Boost',
        );
        expect(watchAdButton, findsOneWidget);

        // Tap Watch Ad
        await tester.tap(watchAdButton);
        await tester.pump();
        expect(
          find.textContaining('Rewarded Video Sponsor Ad'),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 16));
        // Verify Green Success Card & Tap Continue
        final continueButton = find.text('Continue Processing File');
        expect(continueButton, findsOneWidget);
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pump();
        expect(watchAdClicked, isTrue);
      },
    );

    testWidgets('Tapping Cancel invokes onCancel callback', (
      WidgetTester tester,
    ) async {
      bool cancelClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RewardedVideoAdModal(
              filename: 'large_document.pdf',
              fileSizeInBytes: 60 * 1024 * 1024,
              currentLimitMb: 50.0,
              onWatchAd: (boostedLimit) {},
              onCancel: () {
                cancelClicked = true;
              },
            ),
          ),
        ),
      );

      final cancelButton = find.text('Cancel');
      expect(cancelButton, findsOneWidget);
      await tester.tap(cancelButton);
      await tester.pump();
      expect(cancelClicked, isTrue);
    });

    testWidgets(
      'Multi-ad chaining shows step indicators, intermediate milestone, and final unlock',
      (WidgetTester tester) async {
        double finalBoostedLimit = 0.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RewardedVideoAdModal(
                filename: 'test_170mb.pdf',
                fileSizeInBytes: 170 * 1024 * 1024,
                currentLimitMb: 100.0,
                boostPerAdMb: 50.0,
                maxStackMb: 1024.0,
                adDurationSeconds: 15,
                onWatchAd: (boostedLimit) {
                  finalBoostedLimit = boostedLimit;
                },
              ),
            ),
          ),
        );

        // Verify upfront multi-ad requirement is communicated clearly
        expect(find.textContaining('2 Short Ads Required'), findsOneWidget);
        expect(find.textContaining('Ad 1 of 2'), findsWidgets);

        // Verify Watch Ad 1 button
        final watchAd1Button = find.textContaining('Watch Ad 1 of 2');
        expect(watchAd1Button, findsOneWidget);

        // Tap Watch Ad 1
        await tester.tap(watchAd1Button);
        await tester.pump();
        expect(
          find.textContaining('Rewarded Video Sponsor Ad'),
          findsOneWidget,
        );
        expect(find.textContaining('Ad 1 of 2'), findsWidgets);

        // Advance 16 seconds to complete Ad 1
        await tester.pump(const Duration(seconds: 16));

        // Verify Intermediate Milestone is rendered (NOT premature "Continue Processing File")
        expect(find.text('Continue Processing File'), findsNothing);
        expect(find.textContaining('Ad 1 of 2 Complete'), findsOneWidget);
        expect(find.textContaining('150 MB'), findsWidgets);
        expect(find.textContaining('1 more ad needed'), findsOneWidget);

        // Tap Watch Final Ad (Ad 2 of 2)
        final watchAd2Button = find.textContaining(
          'Watch Final Ad (Ad 2 of 2)',
        );
        expect(watchAd2Button, findsOneWidget);
        await tester.tap(watchAd2Button);
        await tester.pump();

        // Verify Ad 2 is playing
        expect(
          find.textContaining('Rewarded Video Sponsor Ad'),
          findsOneWidget,
        );
        expect(find.textContaining('Ad 2 of 2'), findsWidgets);

        // Advance 16 seconds to complete Ad 2
        await tester.pump(const Duration(seconds: 16));

        // Verify Final Success Card is rendered
        expect(find.textContaining('All Quotas Unlocked'), findsOneWidget);
        expect(find.textContaining('200 MB'), findsWidgets);

        // Tap Start/Continue Processing File Now
        final continueButton = find.text('Continue Processing File');
        expect(continueButton, findsOneWidget);
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pump();

        // Verify onWatchAd was called with the full boosted limit (200 MB)
        expect(finalBoostedLimit, equals(200.0));
      },
    );

    testWidgets(
      'When isAdPlaybackEnabled is false (AdSense review mode), unlocks boost instantly without ad countdown',
      (WidgetTester tester) async {
        RewardedVideoAdModal.debugOverrideAdPlayback = false;
        double boostedResult = 0.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RewardedVideoAdModal(
                filename: 'review_oversized.pdf',
                fileSizeInBytes: 60 * 1024 * 1024,
                currentLimitMb: 50.0,
                boostPerAdMb: 50.0,
                maxStackMb: 1024.0,
                onWatchAd: (boostedLimit) {
                  boostedResult = boostedLimit;
                },
              ),
            ),
          ),
        );

        // Verify clean instant boost UI (no fake sponsor ad labels)
        expect(find.text('File Size Limit Exceeded'), findsOneWidget);
        expect(
          find.textContaining('Unlock Ephemeral RAM-Disk Boost'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Unlock Instant Free Boost'),
          findsOneWidget,
        );

        // Tap instant boost
        final instantButton = find.textContaining('Unlock Instant Free Boost');
        await tester.tap(instantButton);
        await tester.pump();

        // Verify no 15-second timer or fake ad video view appeared
        expect(find.textContaining('Rewarded Video Sponsor Ad'), findsNothing);

        // Verify immediate success state
        expect(find.textContaining('All Quotas Unlocked'), findsOneWidget);
        expect(find.textContaining('Each ad watch adds'), findsNothing);
        expect(find.textContaining('Each session boost adds'), findsOneWidget);

        final continueButton = find.text('Continue Processing File');
        expect(continueButton, findsOneWidget);
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pump();

        expect(boostedResult, equals(150.0));
      },
    );
  });
}
