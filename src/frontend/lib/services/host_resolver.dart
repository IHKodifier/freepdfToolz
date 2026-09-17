import 'package:flutter/foundation.dart';

enum AppBrand {
  freeOcr,
  freePdfTools,
}

class HostResolver {
  /// Detects the active brand according to host, query params, or Uri.base
  static AppBrand getBrand({Uri? uri}) {
    final targetUri = uri ?? (kIsWeb ? Uri.base : Uri.parse('https://freepdftoolz.me/'));
    
    // 1. Explicit query parameter override (useful for testing and local dev)
    final brandParam = targetUri.queryParameters['brand']?.toLowerCase();
    if (brandParam == 'freepdftoolz' || brandParam == 'pdf-tools' || brandParam == 'tools') {
      return AppBrand.freePdfTools;
    }
    if (brandParam == 'freeocr' || brandParam == 'ocr') {
      return AppBrand.freeOcr;
    }

    // 2. Domain / Host sniffing
    final host = targetUri.host.toLowerCase();
    if (host.contains('freeocr')) {
      return AppBrand.freeOcr;
    }
    if (host.contains('freepdftoolz') || host.contains('tools.localhost')) {
      return AppBrand.freePdfTools;
    }

    // 3. Standalone FreePDFToolz workspace default
    return AppBrand.freePdfTools;
  }

  static bool isFreeOcrDomain({Uri? uri}) {
    return getBrand(uri: uri) == AppBrand.freeOcr;
  }

  static bool isFreePdfToolsDomain({Uri? uri}) {
    return getBrand(uri: uri) == AppBrand.freePdfTools;
  }

  static String getBrandTitle({Uri? uri}) {
    return getBrand(uri: uri) == AppBrand.freePdfTools ? 'FreePDFToolz' : 'freeOCR.me';
  }

  static String getDefaultHomeRoute({Uri? uri}) {
    return getBrand(uri: uri) == AppBrand.freePdfTools ? '/hub' : '/';
  }
}