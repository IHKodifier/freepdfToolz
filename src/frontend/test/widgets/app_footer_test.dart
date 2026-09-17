import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/constants/social_links.dart';
import 'package:freepdftoolz_frontend/widgets/app_footer.dart';

void main() {
  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  testWidgets(
    'AppFooter renders brand, social media handles, legal links, and engine chips',
    (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(const AppFooter()));
      await tester.pumpAndSettle();

      // Verify Brand title & Privacy commitment text
      expect(find.text('FreePDFToolz'), findsOneWidget);
      expect(find.textContaining('RAM disk'), findsOneWidget);

      // Verify Navigation Buttons
      expect(find.byKey(const Key('footer_home_btn')), findsOneWidget);
      expect(find.byKey(const Key('footer_about_btn')), findsOneWidget);
      expect(find.byKey(const Key('footer_kb_btn')), findsOneWidget);
      expect(find.byKey(const Key('footer_docs_btn')), findsNothing);
      expect(find.byKey(const Key('footer_pdf_tools_btn')), findsNothing);
      expect(find.byKey(const Key('footer_privacy_btn')), findsOneWidget);
      expect(find.byKey(const Key('footer_terms_btn')), findsOneWidget);
      expect(find.byKey(const Key('footer_contact_btn')), findsOneWidget);
      expect(find.byKey(const Key('footer_source_code_btn')), findsOneWidget);

      // Verify Live Social Media Handles (Twitter/X, Instagram, Facebook)
      expect(find.byKey(const Key('footer_social_twitter')), findsOneWidget);
      expect(find.byKey(const Key('footer_social_instagram')), findsOneWidget);
      expect(find.byKey(const Key('footer_social_facebook')), findsOneWidget);
      expect(find.byKey(const Key('footer_social_youtube')), findsNothing);

      // Verify Deprecated Handles are NOT present
      expect(find.byKey(const Key('footer_social_linkedin')), findsNothing);
      expect(find.byKey(const Key('footer_social_discord')), findsNothing);
      expect(find.byKey(const Key('footer_github_repo_link')), findsNothing);

      // Verify Engine Attribution Chips
      expect(find.byKey(const Key('chip_baiduocr')), findsOneWidget);
      expect(find.byKey(const Key('chip_tesseract')), findsOneWidget);
      expect(find.byKey(const Key('chip_ocrmypdf')), findsOneWidget);
      expect(find.byKey(const Key('chip_pymupdf')), findsOneWidget);
    },
  );

  testWidgets(
    'SocialLinks.openSocialChannel triggers high-contrast fallback dialog when URL is unclaimed',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SocialLinks.openSocialChannel(
                  context,
                  platformName: 'Facebook',
                  url: '',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap button to open fallback dialog
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify high-contrast dialog appears
      expect(find.text('Facebook Channel'), findsOneWidget);
      expect(
        find.textContaining('presence is launching soon!'),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Contact Support'), findsOneWidget);

      // Tap Close to dismiss
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Facebook Channel'), findsNothing);
    },
  );

  testWidgets(
    'AppFooter renders FreePDFToolz brand title, copyright, and hub links when on PDF tools route',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(const AppFooter(currentRoute: '/merge')),
      );
      await tester.pumpAndSettle();

      // Verify FreePDFToolz Brand title & Privacy commitment text
      expect(find.text('FreePDFToolz'), findsOneWidget);
      expect(
        find.textContaining(
          'FreePDFToolz.me • 100% Free & Local-First PDF Platform',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Zero retention & RAM disk privacy'),
        findsOneWidget,
      );

      // Verify Navigation Buttons for PDF Tools
      expect(find.text('Tools Hub'), findsOneWidget);
      expect(find.byKey(const Key('footer_home_btn')), findsOneWidget);
      expect(find.text('OCR PDF'), findsOneWidget);
      expect(find.byKey(const Key('footer_ocr_btn')), findsOneWidget);
      expect(find.byKey(const Key('footer_about_btn')), findsOneWidget);
      expect(find.byKey(const Key('footer_kb_btn')), findsOneWidget);
      expect(find.byKey(const Key('footer_privacy_btn')), findsOneWidget);

      // Verify Engine Attribution Chips still present
      expect(find.byKey(const Key('chip_pymupdf')), findsOneWidget);
    },
  );
}
