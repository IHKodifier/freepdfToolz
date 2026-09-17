import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/widgets/app_header.dart';

void main() {
  Widget buildTestWidget({
    required Widget child,
    VoidCallback? onThemeToggle,
    bool isDarkMode = false,
  }) {
    return MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: child,
        ),
      ),
    );
  }

  testWidgets(
    'AppHeader renders brand title, navigation buttons, and theme switcher',
    (WidgetTester tester) async {
      bool toggled = false;

      await tester.pumpWidget(
        buildTestWidget(
          child: AppHeader(
            currentRoute: '/',
            onThemeToggle: () {
              toggled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Brand logo
      expect(find.byKey(const Key('header_brand_logo')), findsOneWidget);

      // Verify Navigation Buttons
      expect(find.byKey(const Key('header_home_btn')), findsOneWidget);
      expect(find.byKey(const Key('header_kb_btn')), findsOneWidget);
      expect(find.byKey(const Key('header_docs_btn')), findsNothing);
      expect(find.byKey(const Key('header_tools_btn')), findsOneWidget);

      // Verify Theme Switcher Button & tap action
      final themeToggleBtn = find.byKey(const Key('header_theme_toggle_btn'));
      expect(themeToggleBtn, findsOneWidget);

      await tester.tap(themeToggleBtn);
      await tester.pumpAndSettle();
      expect(toggled, isTrue);
    },
  );

  testWidgets(
    'AppHeader renders Tools dropdown button when showTools is enabled and displays tool list on tap',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const AppHeader(currentRoute: '/', showTools: true),
        ),
      );
      await tester.pumpAndSettle();

      final toolsBtn = find.byKey(const Key('header_tools_btn'));
      expect(toolsBtn, findsOneWidget);

      await tester.tap(toolsBtn);
      await tester.pumpAndSettle();

      // Should show tools menu items
      expect(find.text('All PDF Tools (16)'), findsOneWidget);
      expect(find.text('Merge PDF'), findsOneWidget);
      expect(find.text('Compress PDF'), findsOneWidget);
      expect(find.text('OCR PDF'), findsOneWidget);
    },
  );
}
