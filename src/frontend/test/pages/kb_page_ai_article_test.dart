import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_ocr_frontend/main.dart';
import 'package:free_ocr_frontend/pages/pdf_tools_hub_page.dart';
import 'package:free_ocr_frontend/pages/kb_page.dart';
import 'package:free_ocr_frontend/widgets/app_footer.dart';
import 'package:free_ocr_frontend/widgets/landing_faq_section.dart';

void main() {
  group('UC-035: AI vs Traditional OCR Article Tests', () {
    testWidgets('KbPage renders AI vs Traditional OCR article via /kb/ai-vs-traditional-ocr route', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(context, '/kb/ai-vs-traditional-ocr');
      await tester.pumpAndSettle();

      expect(find.byType(KbPage), findsOneWidget);
      expect(find.textContaining('Why Deep-Learning AI OCR Outperforms Classical OCR'), findsAtLeast(1));
      expect(find.textContaining('Document Layout Analysis', skipOffstage: false), findsAtLeast(1));
      expect(find.textContaining('Reading Order Detection', skipOffstage: false), findsAtLeast(1));
      expect(find.textContaining('Zero-Disk Retention', skipOffstage: false), findsAtLeast(1));
    });

    testWidgets('KbPage renders AI vs Traditional OCR article via alias /kb/ai-ocr-complex-layouts', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(context, '/kb/ai-ocr-complex-layouts');
      await tester.pumpAndSettle();

      expect(find.byType(KbPage), findsOneWidget);
      expect(find.textContaining('Why Deep-Learning AI OCR Outperforms Classical OCR'), findsAtLeast(1));
    });

    testWidgets('AppFooter includes link to AI vs Traditional OCR article', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppFooter(currentRoute: '/'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('AI vs Traditional OCR'), findsOneWidget);
    });

    testWidgets('LandingFaqSection contains complex layout FAQ item', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LandingFaqSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('complex multi-column'), findsAtLeast(1));
    });

    testWidgets('HomePage renders eye-catching announcement banner for high-fidelity engine upgrade', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pumpAndSettle();
      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(context, '/ocr');
      await tester.pumpAndSettle();

      expect(find.textContaining('Near-Lossless Layout Fidelity'), findsOneWidget);
      expect(find.textContaining('HIGH-FIDELITY UPGRADE'), findsOneWidget);
      expect(find.textContaining('Read Technical Deep-Dive'), findsOneWidget);
    });
  });
}

