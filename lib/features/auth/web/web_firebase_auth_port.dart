/// Narrow Firebase Web Auth surface used by the account ViewModel.
abstract interface class WebFirebaseAuthPort {
  bool get isConfigured;

  String? get currentUid;

  bool get isReadOnly;

  String? get unavailableReason;

  Future<String?> signInWithGoogle();

  Future<String?> signInWithUsername(String username, String password);

  Future<void> linkReadOnlyUsername(String username, String password);

  Future<void> signOut();

  Future<String> tokenFor(String expectedUid);
}

final class WebFirebaseAuthException implements Exception {
  const WebFirebaseAuthException(this.code);

  final String code;

  @override
  String toString() => 'WebFirebaseAuthException($code)';
}
