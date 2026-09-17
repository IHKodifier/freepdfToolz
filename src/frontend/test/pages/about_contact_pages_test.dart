import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/pages/about_page.dart';
import 'package:freepdftoolz_frontend/pages/contact_page.dart';

void main() {
  group('About Page Route & Content Tests', () {
    testWidgets(
      'AboutPage renders mission, RAM disk privacy, and open source engines via /about',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1024);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            initialRoute: '/about',
            routes: {
              '/about': (context) => const AboutPage(),
              '/contact': (context) => const ContactPage(),
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AboutPage), findsOneWidget);
        expect(find.text('ABOUT FREEOCR.ME'), findsOneWidget);
        expect(
          find.textContaining('Democratizing Document OCR'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Founding Mission & Philosophy'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Ephemeral RAM-Disk Security Guarantee'),
          findsOneWidget,
        );
        expect(find.textContaining('Baidu Unlimited OCR'), findsAtLeast(1));
      },
    );
  });

  group('Contact Page Route, Form Validation & Submission Tests', () {
    testWidgets(
      'ContactPage renders channels and validates required fields via /contact',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1024);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            initialRoute: '/contact',
            routes: {'/contact': (context) => const ContactPage()},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ContactPage), findsOneWidget);
        expect(find.text('CONTACT & SUPPORT'), findsOneWidget);
        expect(find.textContaining('support@freeocr.me'), findsAtLeast(1));
        expect(find.textContaining('privacy@freeocr.me'), findsAtLeast(1));

        // Attempt to submit empty form to trigger validation
        final submitBtn = find.byKey(const Key('contact_submit_btn'));
        await tester.ensureVisible(submitBtn);
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        expect(find.text('Please enter your name'), findsOneWidget);
        expect(find.text('Please enter your email address'), findsOneWidget);

        // Fill in valid details
        await tester.enterText(
          find.byKey(const Key('contact_name_field')),
          'AdSense Reviewer',
        );
        await tester.enterText(
          find.byKey(const Key('contact_email_field')),
          'reviewer@google.com',
        );
        await tester.enterText(
          find.byKey(const Key('contact_subject_field')),
          'Domain Evaluation',
        );
        await tester.enterText(
          find.byKey(const Key('contact_message_field')),
          'Testing publisher contactability response flow.',
        );
        await tester.pumpAndSettle();

        // Submit valid form
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        // Expect success view and confirmation message
        expect(find.text('Thank You for Contacting Us!'), findsOneWidget);
        expect(find.textContaining('Message sent!'), findsOneWidget);
      },
    );
  });
}
