import 'package:flutter_test/flutter_test.dart';
import 'package:freepdftoolz_frontend/services/host_resolver.dart';

void main() {
  group('HostResolver Domain & Brand Resolution Tests', () {
    test('detects freeocr.me as FreeOCR brand', () {
      final uri = Uri.parse('https://freeocr.me/');
      expect(HostResolver.isFreeOcrDomain(uri: uri), isTrue);
      expect(HostResolver.isFreePdfToolsDomain(uri: uri), isFalse);
      expect(HostResolver.getBrand(uri: uri), AppBrand.freeOcr);
      expect(HostResolver.getBrandTitle(uri: uri), 'freeOCR.me');
    });

    test(
      'detects freepdftoolz.me, www.freepdftoolz.me, and freepdftoolz.web.app as FreePdfTools brand',
      () {
        final uri = Uri.parse('https://freepdftoolz.me/');
        expect(HostResolver.isFreeOcrDomain(uri: uri), isFalse);
        expect(HostResolver.isFreePdfToolsDomain(uri: uri), isTrue);
        expect(HostResolver.getBrand(uri: uri), AppBrand.freePdfTools);
        expect(HostResolver.getBrandTitle(uri: uri), 'FreePDFToolz');

        final wwwUri = Uri.parse('https://www.freepdftoolz.me/');
        expect(HostResolver.isFreePdfToolsDomain(uri: wwwUri), isTrue);
        expect(HostResolver.getBrand(uri: wwwUri), AppBrand.freePdfTools);

        final webAppUri = Uri.parse('https://freepdftoolz.web.app/');
        expect(HostResolver.isFreePdfToolsDomain(uri: webAppUri), isTrue);
        expect(HostResolver.getBrand(uri: webAppUri), AppBrand.freePdfTools);
      },
    );

    test(
      'freeocr-staging-app.web.app defaults to FreeOCR brand to protect AdSense',
      () {
        final uri = Uri.parse('https://freeocr-staging-app.web.app/');
        expect(HostResolver.isFreeOcrDomain(uri: uri), isTrue);
        expect(HostResolver.isFreePdfToolsDomain(uri: uri), isFalse);
        expect(HostResolver.getBrand(uri: uri), AppBrand.freeOcr);
      },
    );

    test(
      'query parameter brand=freepdftoolz overrides host for local testing',
      () {
        final uri = Uri.parse('http://localhost:8080/?brand=freepdftoolz');
        expect(HostResolver.isFreePdfToolsDomain(uri: uri), isTrue);
        expect(HostResolver.getBrand(uri: uri), AppBrand.freePdfTools);
      },
    );

    test('query parameter brand=freeocr overrides host', () {
      final uri = Uri.parse('https://freepdftoolz.me/?brand=freeocr');
      expect(HostResolver.isFreeOcrDomain(uri: uri), isTrue);
      expect(HostResolver.getBrand(uri: uri), AppBrand.freeOcr);
    });

    test('root route for freeocr brand resolves to / (OCR tool)', () {
      final uri = Uri.parse('https://freeocr.me/');
      expect(HostResolver.getDefaultHomeRoute(uri: uri), '/');
    });

    test('root route for freepdftoolz brand resolves to /hub', () {
      final uri = Uri.parse('https://freepdftoolz.me/');
      expect(HostResolver.getDefaultHomeRoute(uri: uri), '/hub');
    });
  });
}
