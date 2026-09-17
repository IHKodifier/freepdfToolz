import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/widgets/hero_dropzone.dart';

void main() {
  testWidgets(
    'HeroDropzone renders title, drop target, and file picker button',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HeroDropzone())),
      );

      // Verify Title presence
      expect(find.textContaining('Drag & Drop'), findsOneWidget);

      // Verify Icons and Select File button
      expect(find.byIcon(Icons.cloud_upload_rounded), findsOneWidget);
      expect(find.textContaining('Select PDF or Images'), findsOneWidget);
    },
  );
}
