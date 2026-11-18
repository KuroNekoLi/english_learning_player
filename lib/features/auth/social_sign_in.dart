enum SocialProvider {
  google('google.com', 'Google'),
  apple('apple.com', 'Apple');

  const SocialProvider(this.firebaseId, this.label);

  final String firebaseId;
  final String label;
}

abstract interface class SocialSignIn {
  bool isConfigured(SocialProvider provider);
  Future<SocialSignInResult?> signIn(SocialProvider provider);
  Future<void> signOut(SocialProvider provider);
}

sealed class SocialSignInResult {
  const SocialSignInResult();
}

final class ProviderIdToken extends SocialSignInResult {
  const ProviderIdToken(this.idToken, {this.rawNonce});

  final String idToken;
  final String? rawNonce;
}

/// Android's Apple OAuth flow is handled directly by the Firebase SDK.
final class NativeFirebaseUser extends SocialSignInResult {
  const NativeFirebaseUser(this.uid, this.getIdToken);

  final String uid;
  final Future<String> Function() getIdToken;
}
