import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/firebase_account_session.dart';
import '../../core/firebase/firebase_endpoint.dart';
import 'platform_social_sign_in.dart';
import 'social_sign_in.dart';

final firebaseEndpointProvider = Provider<FirebaseEndpoint?>(
  (ref) => FirebaseEndpoint.fromEnvironment(),
);

final firebaseHttpProvider = Provider<FirebaseHttp>((ref) {
  final client = FirebaseHttp();
  ref.onDispose(client.close);
  return client;
});

final firebaseAuthSessionProvider = Provider<FirebaseAccountSession?>((ref) {
  final endpoint = ref.watch(firebaseEndpointProvider);
  return endpoint == null
      ? null
      : FirebaseAccountSession(endpoint, ref.watch(firebaseHttpProvider));
});

final socialSignInProvider = Provider<SocialSignIn?>((ref) {
  final endpoint = ref.watch(firebaseEndpointProvider);
  if (endpoint == null || endpoint.isEmulator) return null;
  return PlatformSocialSignIn(
    project: endpoint.project,
    apiKey: endpoint.apiKey,
  );
});

/// Called before a new account becomes visible to repositories and views.
final beforeAccountChangeProvider = Provider<Future<void> Function()>(
  (ref) => () async {},
);

typedef FirebaseSessionState = ({String? uid});

final firebaseSessionProvider =
    NotifierProvider<FirebaseSessionController, FirebaseSessionState>(
      FirebaseSessionController.new,
    );

final class FirebaseSessionController extends Notifier<FirebaseSessionState> {
  SocialProvider? _signedInProvider;
  bool _changingAccount = false;

  @override
  FirebaseSessionState build() => (uid: null);

  Future<void> signIn(String email, String password) async {
    await _signIn((session) => session.signIn(email, password));
  }

  Future<void> signInWithProvider(SocialProvider provider) async {
    final platform = ref.read(socialSignInProvider);
    if (platform == null || !platform.isConfigured(provider)) {
      throw StateError('The sign-in provider is not configured.');
    }
    await _signIn((session) async {
      try {
        return await session.signInWithProvider(
          provider,
          () => platform.signIn(provider),
        );
      } catch (_) {
        try {
          await platform.signOut(provider);
        } catch (_) {
          // Keep the original sign-in error.
        }
        rethrow;
      }
    }, provider: provider);
  }

  Future<void> _signIn(
    Future<String?> Function(FirebaseAccountSession) authenticate, {
    SocialProvider? provider,
  }) async {
    if (_changingAccount || state.uid != null) return;
    final session = ref.read(firebaseAuthSessionProvider);
    if (session == null) throw StateError('Firebase is not configured.');
    _changingAccount = true;
    try {
      final uid = await authenticate(session);
      if (!ref.mounted || uid == null) return;
      try {
        await ref.read(beforeAccountChangeProvider)();
      } catch (_) {
        session.signOut();
        if (provider != null && ref.mounted) {
          try {
            await ref.read(socialSignInProvider)?.signOut(provider);
          } catch (_) {
            // Keep the account switch failure.
          }
        }
        rethrow;
      }
      if (!ref.mounted) return;
      _signedInProvider = provider;
      state = (uid: uid);
    } finally {
      _changingAccount = false;
    }
  }

  Future<void> signOut() async {
    if (_changingAccount) return;
    final provider = _signedInProvider;
    final platform = ref.read(socialSignInProvider);
    _changingAccount = true;
    try {
      await ref.read(beforeAccountChangeProvider)();
      if (!ref.mounted) return;
      ref.read(firebaseAuthSessionProvider)?.signOut();
      _signedInProvider = null;
      state = (uid: null);
      if (provider != null && platform != null) {
        await platform.signOut(provider);
      }
    } finally {
      _changingAccount = false;
    }
  }
}
