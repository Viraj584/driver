import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._();

  static const String _envBaseUrl = String.fromEnvironment(
    'TRUST_JUGGLER_API_BASE_URL',
    defaultValue: '',
  );

  static String? _customBaseUrl;

  /// Sets or clears a dynamic base URL at runtime.
  static void setBaseUrl(String? url) {
    if (url != null && url.trim().isNotEmpty) {
      _customBaseUrl = _normalizeUrl(url);
    } else {
      _customBaseUrl = null;
    }
  }

  /// Default fallback candidate URLs for local development.
  static List<String> get candidateUrls {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return [_customBaseUrl!];
    }
    if (_envBaseUrl.isNotEmpty) {
      return [_normalizeUrl(_envBaseUrl)];
    }

    if (!kIsWeb && Platform.isAndroid) {
      return [
        'http://127.0.0.1:3000',
        'http://10.0.2.2:3000',
        'http://192.168.1.15:3000',
      ];
    }

    return ['http://127.0.0.1:3000'];
  }

  /// Resolves the base URL for the backend API.
  /// Precedence:
  /// 1. Dynamic override set via setBaseUrl().
  /// 2. TRUST_JUGGLER_API_BASE_URL from environment / dart-define.
  /// 3. Default local development address (http://127.0.0.1:3000).
  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }

    if (_envBaseUrl.isNotEmpty) {
      return _normalizeUrl(_envBaseUrl);
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

