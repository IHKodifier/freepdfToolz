import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/widgets/adsense_banner.dart';

void main() {
  setUp(() {
    AdSenseBanner.kAdSenseApproved = true;
    AdSenseBanner.resetSessionCount();
  });

  testWidgets(
    'AdSenseBanner collapses to SizedBox.shrink when kAdSenseApproved is false',
    (WidgetTester tester) async {
      AdSenseBanner.kAdSenseApproved = false;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdSenseBanner())),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adsense_banner_container')), findsNothing);
    },
  );

  testWidgets(
    'AdSenseBanner renders static compliant banner layout correctly',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AdSenseBanner())),
      );
      await tester.pumpAndSettle();

      // Verify banner container, AD badge, and sponsored text exists
      expect(find.byKey(const Key('adsense_banner_container')), findsOneWidget);
      expect(find.text('AD'), findsOneWidget);
      expect(find.text('Sponsored Advertisement'), findsOneWidget);
      expect(find.textContaining('Google AdSense'), findsOneWidget);
    },
  );

  testWidgets('AdSenseBanner methods execute safely as no-ops without error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AdSenseBanner())),
    );
    await tester.pumpAndSettle();

    // Verify calling rotateAd or resetSessionCount does not throw and preserves static UI
    expect(() => AdSenseBanner.rotateAd(), returnsNormally);
    expect(() => AdSenseBanner.resetSessionCount(), returnsNormally);
    await tester.pump();

    expect(find.byKey(const Key('adsense_banner_container')), findsOneWidget);
  });
}
