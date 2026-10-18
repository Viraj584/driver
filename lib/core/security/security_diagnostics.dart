import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Debug-only diagnostics. Never include credentials or user supplied values.
class SecurityDiagnostics {
  SecurityDiagnostics._();

  static int _sequence = 0;

  static String newCorrelationId() =>
      '${DateTime.now().toUtc().microsecondsSinceEpoch}-${++_sequence}';

  static void failure({
    required String operation,
    required String correlationId,
    String? callableName,
    required String exceptionCode,
  }) {
    if (!kDebugMode) return;
    developer.log(
      'operation=$operation callable=${callableName ?? 'none'} '
      'exception_code=$exceptionCode platform=${kIsWeb ? 'web' : defaultTargetPlatform.name} '
      'correlation_id=$correlationId',
      name: 'TrustJuggler.Security',
      level: 900,
    );
  }
}
