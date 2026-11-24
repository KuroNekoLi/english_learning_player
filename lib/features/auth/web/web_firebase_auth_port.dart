/// Narrow Firebase Web Auth surface used by the account ViewModel.
abstract interface class WebFirebaseAuthPort {
  bool get isConfigured;

  String? get currentUid;

  String? get cloudUid;

  bool get isReadOnly;

  bool get canProvisionReadOnlyLogin;

  String? get unavailableReason;

  Future<String?> signInWithGoogle();

  Future<String?> signInWithUsername(String username, String password);

  Future<String> provisionReadOnlyLogin(String username, String password);

  Future<void> signOut();

  Future<String> tokenFor(String expectedUid);
}

final class WebFirebaseAuthException implements Exception {
  const WebFirebaseAuthException(this.code);

  final String code;

  @override
  String toString() => 'WebFirebaseAuthException($code)';
}
