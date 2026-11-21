/// Narrow Firebase Web Auth surface used by the account ViewModel.
abstract interface class WebFirebaseAuthPort {
  bool get isConfigured;

  String? get currentUid;

  String? get unavailableReason;

  Future<String?> signInWithGoogle();

  Future<void> signOut();

  Future<String> tokenFor(String expectedUid);
}

final class WebFirebaseAuthException implements Exception {
  const WebFirebaseAuthException(this.code);

  final String code;

  @override
  String toString() => 'WebFirebaseAuthException($code)';
}
