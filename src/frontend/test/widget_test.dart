import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_ocr_frontend/main.dart';
import 'package:free_ocr_frontend/pages/pdf_tools_hub_page.dart';

void main() {
  testWidgets('App renders FreePDFToolz hub and uses Material 3 theme', (WidgetTester tester) async {
    await tester.pumpWidget(const FreeOcrApp());
    await tester.pumpAndSettle();

    expect(find.byType(PdfToolsHubPage), findsOneWidget);
    expect(find.textContaining('FreePDFToolz'), findsAtLeast(1));

    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.theme?.useMaterial3, isTrue);
    expect(app.darkTheme?.useMaterial3, isTrue);
  });
}