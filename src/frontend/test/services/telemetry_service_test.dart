import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/services/telemetry_service.dart';

void main() {
  group('TelemetryService Unit & FreePDFToolz Telemetry Tests', () {
    test('trackPageView dispatches pageview without throwing', () {
      expect(
        () =>
            TelemetryService.trackPageView('/', pageTitle: 'freeOCR.me — Home'),
        returnsNormally,
      );
      expect(
        () => TelemetryService.trackPageView(
          '/result/job_abc123',
          pageTitle: 'Result',
        ),
        returnsNormally,
      );
    });

    test('test_track_page_view_dispatches_for_freepdftoolz_routes', () {
      // Hub & FreePDFToolz tools
      expect(
        () => TelemetryService.trackPageView(
          '/pdf-tools',
          pageTitle: 'FreePDFToolz — All PDF Tools',
        ),
        returnsNormally,
      );
      expect(
        () => TelemetryService.trackPageView(
          '/sign/process',
          pageTitle: 'FreePDFToolz — Sign PDF (Workspace)',
        ),
        returnsNormally,
      );
      expect(
        () => TelemetryService.trackPageView(
          '/merge/process',
          pageTitle: 'FreePDFToolz — Merge PDF',
        ),
        returnsNormally,
      );
      expect(
        () => TelemetryService.trackPageView(
          '/compress',
          pageTitle: 'FreePDFToolz — Compress PDF',
        ),
        returnsNormally,
      );
    });

    test('test_tool_conversion_events_format', () {
      // 1. Tool upload started
      expect(
        () => TelemetryService.trackToolUploadStarted(
          tool: 'merge',
          fileSizeKb: 1024.5,
        ),
        returnsNormally,
      );

      // 2. Tool process completed
      expect(
        () => TelemetryService.trackToolProcessCompleted(
          tool: 'compress',
          durationMs: 1420,
          pages: 12,
        ),
        returnsNormally,
      );

      // 3. Tool download clicked
      expect(
        () => TelemetryService.trackToolDownloadClicked(
          tool: 'split',
          fileSizeKb: 850.0,
        ),
        returnsNormally,
      );

      // 4. Rewarded ad watched
      expect(
        () => TelemetryService.trackRewardedAdWatched(
          tool: 'redact',
          boostMb: 50.0,
        ),
        returnsNormally,
      );
    });

    test('trackEvent dispatches generic event without throwing', () {
      expect(
        () => TelemetryService.trackEvent('test_event', {'param_1': 'value_1'}),
        returnsNormally,
      );
    });

    test(
      'trackDocumentUploaded dispatches upload telemetry without throwing',
      () {
        expect(
          () => TelemetryService.trackDocumentUploaded(
            filename: 'sample_doc.pdf',
            fileSizeInBytes: 2048576,
            source: 'unit_test',
          ),
          returnsNormally,
        );
      },
    );

    test(
      'trackOcrCompleted dispatches OCR complete telemetry without throwing',
      () {
        expect(
          () => TelemetryService.trackOcrCompleted(
            jobId: 'job_test_456',
            pageCount: 5,
            durationSeconds: 2.5,
            layoutType: 'simple',
          ),
          returnsNormally,
        );
      },
    );

    test(
      'trackDownloadClicked dispatches download telemetry without throwing',
      () {
        expect(
          () => TelemetryService.trackDownloadClicked(
            jobId: 'job_test_789',
            format: 'pdf',
            filename: 'sample_doc_searchable.pdf',
          ),
          returnsNormally,
        );
      },
    );

    test('trackEmailSent dispatches email telemetry without throwing', () {
      expect(
        () => TelemetryService.trackEmailSent(
          jobId: 'job_test_789',
          recipientDomain: 'example.com',
        ),
        returnsNormally,
      );
    });
  });
}
