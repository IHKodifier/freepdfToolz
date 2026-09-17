import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/main.dart';

void main() {
  testWidgets('AppBar contains Theme Toggle button and toggles theme mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FreeOcrApp());
    await tester.pumpAndSettle();

    // Verify Theme Toggle IconButton exists in AppHeader
    final toggleFinder = find.byKey(const Key('header_theme_toggle_btn'));
    expect(toggleFinder, findsOneWidget);

    // Tap theme toggle button
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    // Verify tooltip updated to Light Mode
    expect(find.byTooltip('Switch to Light Mode'), findsOneWidget);

    // Tap theme toggle button again to switch back
    await tester.tap(find.byTooltip('Switch to Light Mode'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Switch to Dark Mode'), findsOneWidget);
  });
}
