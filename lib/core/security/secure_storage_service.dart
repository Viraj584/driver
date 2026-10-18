import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small interface keeps the secure-storage plugin replaceable in tests.
abstract interface class SecureKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  static const androidOptions = AndroidOptions(
    resetOnError: false,
    migrateWithBackup: true,
  );

  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: androidOptions);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Allows only app-session namespaced values, never user tokens or credentials.
class SecureStorageService {
  SecureStorageService({required this.store});

  final SecureKeyValueStore store;
  static const _prefix = 'trust_juggler.session.';
  static const sessionDataKeys = <String>{'ephemeral_session_material'};

  String _key(String name) {
    if (!sessionDataKeys.contains(name)) {
      throw ArgumentError.value(name, 'name', 'Unsupported session data key');
    }
    return '$_prefix$name';
  }

  Future<String?> readSessionData(String name) => store.read(key: _key(name));

  Future<void> writeSessionData(String name, String value) =>
      store.write(key: _key(name), value: value);

  Future<void> deleteSessionData(String name) => store.delete(key: _key(name));

  Future<void> clearSessionData() async {
    for (final name in sessionDataKeys) {
      await deleteSessionData(name);
    }
  }
}
