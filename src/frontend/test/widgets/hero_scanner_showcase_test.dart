import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/widgets/hero_scanner_showcase.dart';

void main() {
  testWidgets(
    'HeroScannerShowcase renders engine badge, flow pill, and metric cards',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HeroScannerShowcase())),
      );

      // Verify Title & Status
      expect(find.text('NEURAL OCR ENGINE'), findsOneWidget);
      expect(find.text('File Size up to 1 GB'), findsOneWidget);

      // Verify Metric Chips
      expect(find.text('RAM-DISK SECURITY'), findsOneWidget);
      expect(find.text('Zero File Retention'), findsOneWidget);
      expect(find.text('Auto-purged post OCR'), findsOneWidget);

      expect(find.text('DUAL-LAYER PDF'), findsOneWidget);
      expect(find.text('Searchable & Selectable'), findsOneWidget);
      expect(find.text('Full text + layout fidelity'), findsOneWidget);
    },
  );
}
