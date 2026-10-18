import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../network/api_client.dart';
import 'auth_gateway.dart';
import 'credential_policy.dart';

class LocalBackendUser implements User {
  LocalBackendUser({
    required this.uid,
    this.email,
    this.phoneNumber,
    this.displayName,
    this.role = 'driver',
    this.token,
  });

  @override
  final String uid;

  @override
  final String? email;

  @override
  final String? phoneNumber;

  @override
  final String? displayName;

  final String role;
  final String? token;

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    return _LocalIdTokenResult({
      'admin': role == 'admin',
      'user_id': uid,
      'email': email,
      'role': role,
    });
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => token;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LocalIdTokenResult implements IdTokenResult {
  _LocalIdTokenResult(this._claims);
  final Map<String, dynamic> _claims;

  @override
  Map<String, dynamic>? get claims => _claims;

  @override
  DateTime? get expirationTime => DateTime.now().add(const Duration(minutes: 15));

  @override
  DateTime? get issuedAtTime => DateTime.now();

  @override
  DateTime? get authTime => DateTime.now();

  @override
  String? get signInProvider => 'password';

  @override
  String? get token => 'local-mock-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LocalBackendAuthGateway implements AuthGateway, PasswordAuthGateway {
  LocalBackendAuthGateway({
    required this.apiClient,
    User? initialUser,
  }) : _currentUser = initialUser {
    if (initialUser != null) {
      _userStreamController.add(initialUser);
    }
  }

  final ApiClient apiClient;
  final StreamController<User?> _userStreamController =
      StreamController<User?>.broadcast();

  User? _currentUser;
  String? _lastPhoneVerificationId;
  String? get lastPhoneVerificationId => _lastPhoneVerificationId;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<User?> get userChanges => _userStreamController.stream;

  @override
  Future<void> signInWithEmailPassword(String email, String password) async {
    final normalized = email.trim();
    if (!normalized.contains('@') || password.isEmpty) {
      throw const FormatException('Enter a valid email and password.');
    }

    final response = await apiClient.post(
      '/api/auth/login',
      body: {
        'email': normalized,
        'password': password,
      },
    );

    _handleAuthSuccess(response);
  }

  @override
  Future<void> createEmailPasswordAccount(String email, String password) async {
    final normalized = email.trim();
    if (!normalized.contains('@') || password.length < 8) {
      throw const FormatException(
        'Enter a valid email and a password with at least 8 characters.',
      );
    }

    final response = await apiClient.post(
      '/api/auth/register',
      body: {
        'email': normalized,
        'password': password,
        'role': 'driver',
      },
    );

    _handleAuthSuccess(response);
  }

  @override
  Future<void> sendPhoneCode(
    String phoneNumber,
    void Function(String) onCodeSent,
  ) async {
    final normalized = normalizeE164PhoneNumber(phoneNumber);
    final response = await apiClient.post(
      '/api/auth/phone-code',
      body: {'phoneNumber': normalized},
    );

    final data = response['data'] as Map<String, dynamic>;
    final vId = data['verificationId'] as String;
    _lastPhoneVerificationId = vId;
    onCodeSent(vId);
  }

  @override
  Future<void> verifyPhoneCode(String verificationId, String code) async {
    final cleanCode = code.trim();
    final response = await apiClient.post(
      '/api/auth/verify-phone-code',
      body: {
        'verificationId': verificationId,
        'code': cleanCode,
      },
    );

    _handleAuthSuccess(response);
  }

  @override
  Future<void> sendEmailLink(String email) async {
    // Development passwordless link simulation
    final normalized = email.trim();
    if (!normalized.contains('@')) {
      throw const FormatException('Enter a valid email.');
    }
  }

  @override
  Future<void> finishEmailLink(String email, String link) async {
    // In local mode, passwordless link authenticates as user
    final normalized = email.trim();
    try {
      await signInWithEmailPassword(normalized, 'Password123!');
    } catch (_) {
      await createEmailPasswordAccount(normalized, 'Password123!');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await apiClient.post('/api/auth/logout');
    } catch (_) {
      // Best-effort server logout
    } finally {
      apiClient.clearTokens();
      _currentUser = null;
      _userStreamController.add(null);
    }
  }

  void _handleAuthSuccess(Map<String, dynamic> response) {
    final data = response['data'] as Map<String, dynamic>;
    final token = data['token'] as String;
    final refreshToken = data['refreshToken'] as String?;
    final userData = data['user'] as Map<String, dynamic>;

    apiClient.setTokens(accessToken: token, refreshToken: refreshToken);

    final user = LocalBackendUser(
      uid: userData['id'] as String,
      email: userData['email'] as String?,
      phoneNumber: userData['phone'] as String?,
      displayName: userData['email'] ?? userData['phone'] ?? 'Driver',
      role: userData['role'] as String? ?? 'driver',
      token: token,
    );

    _currentUser = user;
    _userStreamController.add(user);
  }
}
