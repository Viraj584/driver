import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._();

  static const String _envBaseUrl = String.fromEnvironment(
    'TRUST_JUGGLER_API_BASE_URL',
    defaultValue: '',
  );

  /// Resolves the base URL for the backend API.
  /// Precedence:
  /// 1. TRUST_JUGGLER_API_BASE_URL from environment / dart-define.
  /// 2. If running on an Android physical device or emulator:
  ///    - Android emulator default: http://10.0.2.2:3000
  /// 3. Otherwise (Desktop, Web, iOS simulator, unit test):
  ///    - http://127.0.0.1:3000
  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _normalizeUrl(_envBaseUrl);
    }

    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    }

    return 'http://127.0.0.1:3000';
  }

  static String resolveBaseUrl() => baseUrl;

  static String _normalizeUrl(String url) {
    var trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// Timeout duration for API operations.
  static const Duration timeout = Duration(seconds: 12);
}
