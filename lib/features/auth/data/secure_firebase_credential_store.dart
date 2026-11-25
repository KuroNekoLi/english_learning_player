import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'firebase_credential_store.dart';

final class SecureFirebaseCredentialStore implements FirebaseCredentialStore {
  SecureFirebaseCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage;

  static const _key = 'firebase_auth_session_v1';
  static const _defaultStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
