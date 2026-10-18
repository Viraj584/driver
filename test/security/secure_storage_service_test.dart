import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/core/security/secure_storage_service.dart';

class FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read({required String key}) async {
    if (fail) throw StateError('storage error');
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    if (fail) throw StateError('storage error');
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    if (fail) throw StateError('storage error');
    values.remove(key);
  }
}

void main() {
  test(
    'Android storage options use default Keystore ciphers and surface errors',
    () {
      final options = FlutterSecureKeyValueStore.androidOptions.toMap();
      expect(
        options['keyCipherAlgorithm'],
        'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
      );
      expect(options['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
      expect(options['resetOnError'], 'false');
      expect(options['migrateWithBackup'], 'true');
    },
  );

  test(
    'session data is namespaced and can be read, written, and deleted',
    () async {
      final store = FakeStore();
      final service = SecureStorageService(store: store);
      await service.writeSessionData('ephemeral_session_material', 'test-only');
      expect(
        store.values.keys.single,
        'trust_juggler.session.ephemeral_session_material',
      );
      expect(
        await service.readSessionData('ephemeral_session_material'),
        'test-only',
      );
      await service.clearSessionData();
      expect(store.values, isEmpty);
    },
  );

  test(
    'unsupported keys and storage errors are not silently downgraded',
    () async {
      final store = FakeStore();
      final service = SecureStorageService(store: store);
      expect(
        () => service.readSessionData('access_token'),
        throwsArgumentError,
      );
      store.fail = true;
      await expectLater(
        service.readSessionData('ephemeral_session_material'),
        throwsStateError,
      );
      await expectLater(
        service.writeSessionData('ephemeral_session_material', 'secret'),
        throwsStateError,
      );
    },
  );
}
