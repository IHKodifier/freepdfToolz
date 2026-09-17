import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freepdftoolz_frontend/pages/pdf_tools_hub_page.dart';
import 'package:freepdftoolz_frontend/widgets/tool_card.dart';
import 'package:freepdftoolz_frontend/services/favorites_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FavoritesService.init();
  });

  Widget buildTestHub() {
    return MaterialApp(
      routes: {
        '/merge': (context) => const Scaffold(body: Text('Merge Page')),
        '/split': (context) => const Scaffold(body: Text('Split Page')),
        '/ocr': (context) => const Scaffold(body: Text('OCR Page')),
      },
      home: const PdfToolsHubPage(),
    );
  }

  testWidgets(
    'PdfToolsHubPage renders header, retention pill, search field, and all 16 tool cards',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHub());
      await tester.pumpAndSettle();

      // Verify Title / Header
      expect(find.textContaining('PDF Tools Suite'), findsOneWidget);
      expect(find.textContaining('Zero File Retention'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify tool cards count (all 16 tools)
      expect(find.byType(ToolCard), findsNWidgets(16));

      // Verify key tool cards are visible
      expect(find.widgetWithText(ToolCard, 'Merge PDF'), findsOneWidget);
      expect(find.widgetWithText(ToolCard, 'Split PDF'), findsOneWidget);
      expect(find.widgetWithText(ToolCard, 'Compress PDF'), findsOneWidget);
      expect(find.widgetWithText(ToolCard, 'OCR PDF'), findsOneWidget);
      expect(find.widgetWithText(ToolCard, 'Sign PDF'), findsOneWidget);
    },
  );

  testWidgets('PdfToolsHubPage filters tools by search query in real time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestHub());
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'Merge');
    await tester.pumpAndSettle();

    // Only Merge card should be visible
    expect(find.text('Merge PDF'), findsOneWidget);
    expect(find.text('Split PDF'), findsNothing);
    expect(find.text('Compress PDF'), findsNothing);
  });

  testWidgets(
    'PdfToolsHubPage supports favoriting tools and filtering by Favorites',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHub());
      await tester.pumpAndSettle();

      // Verify initial filter chips: All (16) and Favorites (0)
      expect(find.text('All (16)'), findsOneWidget);
      expect(find.text('♥ Favorites (0)'), findsOneWidget);

      // Tap Favorites chip with 0 favorited -> Shows empty state
      await tester.tap(find.text('♥ Favorites (0)'));
      await tester.pumpAndSettle();

      expect(find.text('No Favorite PDF Tools Yet'), findsOneWidget);
      expect(find.byType(ToolCard), findsNothing);

      // Switch back to All (16)
      await tester.tap(find.text('Browse All 16 Tools'));
      await tester.pumpAndSettle();
      expect(find.byType(ToolCard), findsNWidgets(16));

      // Favorite 'Merge PDF' by tapping its heart icon
      final mergeHeartBtn = find.descendant(
        of: find.widgetWithText(ToolCard, 'Merge PDF'),
        matching: find.byTooltip('Add to favorites'),
      );
      expect(mergeHeartBtn, findsOneWidget);
      await tester.tap(mergeHeartBtn);
      await tester.pumpAndSettle();

      // Verify filter chip updated to ♥ Favorites (1)
      expect(find.text('♥ Favorites (1)'), findsOneWidget);

      // Filter by Favorites
      await tester.tap(find.text('♥ Favorites (1)'));
      await tester.pumpAndSettle();

      // Only 'Merge PDF' should be visible
      expect(find.text('Merge PDF'), findsOneWidget);
      expect(find.text('Split PDF'), findsNothing);

      // Verify SemanticHeartIcon is rendered with filled state
      final filledHeartIcon = find.descendant(
        of: find.widgetWithText(ToolCard, 'Merge PDF'),
        matching: find.byWidgetPredicate(
          (w) => w is SemanticHeartIcon && w.isFilled == true,
        ),
      );
      expect(filledHeartIcon, findsOneWidget);
    },
  );

  testWidgets('Tapping a ToolCard navigates to corresponding route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestHub());
    await tester.pumpAndSettle();

    final mergeCard = find.text('Merge PDF');
    expect(mergeCard, findsOneWidget);
    await tester.ensureVisible(mergeCard);
    await tester.pumpAndSettle();
    await tester.tap(mergeCard);
    await tester.pumpAndSettle();

    // Should have navigated to Merge Page
    expect(find.text('Merge Page'), findsOneWidget);
  });
}
