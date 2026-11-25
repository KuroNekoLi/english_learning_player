/// Persists Firebase credentials between native app launches.
///
/// Implementations must store the value in platform secure storage. Web auth
/// uses Firebase Auth's own browser persistence and does not use this port.
abstract interface class FirebaseCredentialStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> clear();
}

final class MemoryFirebaseCredentialStore implements FirebaseCredentialStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
