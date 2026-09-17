import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:free_ocr_frontend/main.dart';
import 'package:free_ocr_frontend/pages/pdf_tools_hub_page.dart';

void main() {
  group('Knowledge Base Page Navigation & Content Tests', () {
    testWidgets('KbPage renders header, segment tabs, and open-source links via /kb route', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(context, '/kb');
      await tester.pumpAndSettle();

      expect(find.textContaining('Knowledge Base'), findsAtLeast(1));
      expect(find.byKey(const Key('kb_segmented_tabs')), findsOneWidget);
      expect(find.textContaining('Complete Guide to OCR'), findsAtLeast(1));
      expect(find.textContaining('Baidu AI Research', skipOffstage: false), findsAtLeast(1));
      expect(find.textContaining('tesseract-ocr/tesseract', skipOffstage: false), findsAtLeast(1));
    });

    testWidgets('KbPage article slug navigation /kb/pdf-standards renders PDF History Wiki', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(context, '/kb/pdf-standards');
      await tester.pumpAndSettle();

      expect(find.textContaining('Evolution of PDF'), findsAtLeast(1));
      expect(find.textContaining('ocrmypdf/OCRmyPDF', skipOffstage: false), findsAtLeast(1));
      expect(find.textContaining('pymupdf/PyMuPDF', skipOffstage: false), findsAtLeast(1));
    });
  });

  group('Disabled /docs Route Fallback Tests', () {
    testWidgets('/docs safely falls back to HomePage without exposing teaser or ads', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(context, '/docs');
      await tester.pumpAndSettle();

      expect(find.byType(PdfToolsHubPage), findsOneWidget);
      expect(find.textContaining('API Access Coming Soon'), findsNothing);
    });
  });

  group('Privacy & Terms Pages Navigation Tests', () {
    testWidgets('PrivacyPage renders GDPR, CCPA & RAM disclosures via /privacy route', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(context, '/privacy');
      await tester.pumpAndSettle();

      expect(find.textContaining('Privacy Policy'), findsAtLeast(1));
      expect(find.textContaining('GDPR', skipOffstage: false), findsAtLeast(1));
      expect(find.textContaining('CCPA', skipOffstage: false), findsAtLeast(1));
      expect(find.textContaining('Zero Persistent Document Storage Guarantee', skipOffstage: false), findsAtLeast(1));
      expect(find.textContaining('Google AdSense', skipOffstage: false), findsAtLeast(1));
    });

    testWidgets('TermsPage renders open source licenses & Baidu OCR via /terms route', (WidgetTester tester) async {
      await tester.pumpWidget(const FreeOcrApp());
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(PdfToolsHubPage));
      Navigator.pushNamed(context, '/terms');
      await tester.pumpAndSettle();

      expect(find.textContaining('Terms of Service'), findsAtLeast(1));
      expect(find.textContaining('Acceptable Use', skipOffstage: false), findsAtLeast(1));
      expect(find.textContaining('Baidu\'s Unlimited OCR', skipOffstage: false), findsAtLeast(1));
      expect(find.textContaining('GPL-3.0', skipOffstage: false), findsAtLeast(1));
    });
  });
}
