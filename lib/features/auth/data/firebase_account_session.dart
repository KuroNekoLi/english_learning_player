import 'dart:convert';

import '../../../core/sync/sync_contracts.dart';
import '../social_sign_in.dart';
import '../../../core/firebase/firebase_endpoint.dart';
import 'firebase_identity_session.dart';
import '../username_login.dart';

/// The active account used by all Firebase synchronization transports.
final class FirebaseAccountSession implements FirebaseIdentitySession {
  FirebaseAccountSession(this.endpoint, this.http);

  final FirebaseEndpoint endpoint;
  final FirebaseHttp http;
  _Credentials? _credentials;
  NativeFirebaseUser? _nativeUser;
  bool _readOnly = false;
  Future<_Credentials>? _renewing;
  int _generation = 0;

  @override
  String? get uid => _credentials?.uid ?? _nativeUser?.uid;

  /// Password credentials are intentionally read-only in Firebase Rules.
  @override
  bool get isReadOnly => _readOnly;

  bool get canLinkUsernamePassword => _credentials != null && !_readOnly;

  @override
  Future<SyncIdentity?> currentIdentity() async =>
      uid == null ? null : SyncIdentity(uid!);

  Future<String> signIn(
    String email,
    String password, {
    bool readOnly = false,
  }) async {
    signOut();
    final generation = _generation;
    final response = await http.send(
      'POST',
      endpoint.auth('signInWithPassword'),
      contentType: 'application/json',
      bytes: FirebaseHttp.encode({
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      }),
    );
    if (response.statusCode == 400) {
      await http.read(response).drain<void>();
      throw const SyncFailure(
        SyncFailureKind.unauthenticated,
        'sign_in_rejected',
      );
    }
    await http.requireSuccess(response);
    final credentials = _Credentials.parse(await http.json(response));
    if (_generation != generation) _notSignedIn();
    _credentials = credentials;
    _readOnly = readOnly;
    return credentials.uid;
  }

  Future<String> signInWithUsername(String username, String password) {
    final normalized = normalizeLoginUsername(username);
    if (!isReadOnlyLoginUsername(normalized) ||
        !isSupportedReadOnlyLoginProject(endpoint.project)) {
      throw const SyncFailure(SyncFailureKind.invalidData, 'invalid_username');
    }
    return signIn(
      loginEmail(normalized, endpoint.project),
      password,
      readOnly: isReadOnlyLoginUsername(normalized),
    );
  }

  /// Adds a username/password credential to the current Google account.
  /// Firebase keeps the same UID, so existing cloud data stays in place.
  Future<void> linkReadOnlyUsername({
    required String username,
    required String password,
  }) async {
    final normalized = normalizeLoginUsername(username);
    if (!isReadOnlyLoginUsername(normalized) ||
        !isSupportedReadOnlyLoginProject(endpoint.project)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'unsupported_username_credential',
      );
    }
    if (password.length < 12) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'password_too_short',
      );
    }
    final current = _credentials;
    if (current == null || _readOnly) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'google_owner_session_required',
      );
    }
    final generation = _generation;
    final token = await tokenFor(current.uid);
    final response = await http.send(
      'POST',
      endpoint.auth('update'),
      contentType: 'application/json',
      bytes: FirebaseHttp.encode({
        'idToken': token,
        'email': loginEmail(normalized, endpoint.project),
        'password': password,
        'returnSecureToken': true,
      }),
    );
    if (response.statusCode == 400) {
      await http.read(response).drain<void>();
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'username_credential_unavailable',
      );
    }
    await http.requireSuccess(response);
    final linked = _Credentials.parse(await http.json(response));
    if (_generation != generation || linked.uid != current.uid) {
      _notSignedIn();
    }
    _credentials = linked;
    // Require a fresh Google sign-in before using the writer session.
    signOut();
  }

  Future<String?> signInWithProvider(
    SocialProvider provider,
    Future<SocialSignInResult?> Function() authorize,
  ) async {
    if (uid != null) throw StateError('Sign out before changing accounts.');
    final generation = ++_generation;
    final result = await authorize();
    if (_generation != generation) _notSignedIn();
    switch (result) {
      case null:
        return null;
      case NativeFirebaseUser(:final uid):
        if (provider != SocialProvider.apple || !_validUid(uid)) {
          throw const SyncFailure(
            SyncFailureKind.invalidData,
            'invalid_auth_response',
          );
        }
        await result.getIdToken();
        if (_generation != generation) _notSignedIn();
        _nativeUser = result;
        _readOnly = false;
        return uid;
      case ProviderIdToken(:final idToken, :final rawNonce):
        if (idToken.isEmpty ||
            (provider == SocialProvider.apple && (rawNonce?.isEmpty ?? true))) {
          throw const SyncFailure(
            SyncFailureKind.invalidData,
            'invalid_provider_credential',
          );
        }
        final response = await http.send(
          'POST',
          endpoint.auth('signInWithIdp'),
          contentType: 'application/json',
          bytes: FirebaseHttp.encode({
            'requestUri': endpoint.isEmulator
                ? 'http://localhost'
                : 'https://${endpoint.project}.firebaseapp.com/__/auth/handler',
            'postBody': Uri(
              queryParameters: {
                'providerId': provider.firebaseId,
                'id_token': idToken,
                'nonce': ?rawNonce,
              },
            ).query,
            'returnIdpCredential': true,
            'returnSecureToken': true,
          }),
        );
        if (response.statusCode == 400) {
          final error = (await http.json(response))['error'];
          if (error is Map && _needsAccountLink(error['message'])) {
            _accountLinkRequired();
          }
          throw const SyncFailure(
            SyncFailureKind.unauthenticated,
            'sign_in_rejected',
          );
        }
        await http.requireSuccess(response);
        final data = await http.json(response);
        if (data['needConfirmation'] == true ||
            _needsAccountLink(data['errorMessage'])) {
          _accountLinkRequired();
        }
        final credentials = _Credentials.parse(data);
        if (_generation != generation) _notSignedIn();
        _credentials = credentials;
        _readOnly = false;
        return credentials.uid;
    }
  }

  void signOut() {
    _generation++;
    _credentials = null;
    _nativeUser = null;
    _readOnly = false;
    _renewing = null;
  }

  @override
  Future<String> tokenFor(String expectedUid) async {
    final native = _nativeUser;
    if (native != null) {
      if (native.uid != expectedUid) _notSignedIn();
      final generation = _generation;
      final token = await native.getIdToken();
      if (_generation != generation) _notSignedIn();
      return token;
    }
    final current = _credentials;
    if (current == null || current.uid != expectedUid) _notSignedIn();
    if (current.expiresAt.isAfter(
      DateTime.now().add(const Duration(minutes: 1)),
    )) {
      return current.token;
    }
    final generation = _generation;
    final renew = _renewing ??= _refresh(current);
    try {
      final updated = await renew;
      if (_generation != generation || updated.uid != expectedUid) {
        _notSignedIn();
      }
      _credentials = updated;
      return updated.token;
    } finally {
      if (identical(_renewing, renew)) _renewing = null;
    }
  }

  Future<_Credentials> _refresh(_Credentials current) async {
    final response = await http.send(
      'POST',
      endpoint.refresh,
      contentType: 'application/x-www-form-urlencoded',
      bytes: utf8.encode(
        Uri(
          queryParameters: {
            'grant_type': 'refresh_token',
            'refresh_token': current.refresh,
          },
        ).query,
      ),
    );
    if (response.statusCode == 400) {
      await http.read(response).drain<void>();
      _notSignedIn();
    }
    await http.requireSuccess(response);
    return _Credentials.parse(await http.json(response), refreshed: true);
  }

  static Never _notSignedIn() => throw const SyncFailure(
    SyncFailureKind.unauthenticated,
    'firebase_sign_in_required',
  );

  static bool _needsAccountLink(Object? error) =>
      error is String &&
      const [
        'EMAIL_EXISTS',
        'ACCOUNT_EXISTS_WITH_DIFFERENT_CREDENTIAL',
        'FEDERATED_USER_ID_ALREADY_LINKED',
      ].any(error.startsWith);

  static Never _accountLinkRequired() => throw const SyncFailure(
    SyncFailureKind.unauthenticated,
    'sign_in_account_link_required',
  );
}

bool _validUid(String uid) => uid.isNotEmpty && !uid.contains('/');

final class _Credentials {
  const _Credentials(this.uid, this.token, this.refresh, this.expiresAt);

  factory _Credentials.parse(
    Map<String, dynamic> data, {
    bool refreshed = false,
  }) {
    final uid = data[refreshed ? 'user_id' : 'localId'];
    final token = data[refreshed ? 'id_token' : 'idToken'];
    final refresh = data[refreshed ? 'refresh_token' : 'refreshToken'];
    final expiry = int.tryParse(
      '${data[refreshed ? 'expires_in' : 'expiresIn']}',
    );
    if (uid is! String ||
        !_validUid(uid) ||
        token is! String ||
        token.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        expiry == null ||
        expiry <= 0) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'invalid_auth_response',
      );
    }
    return _Credentials(
      uid,
      token,
      refresh,
      DateTime.now().add(Duration(seconds: expiry)),
    );
  }

  final String uid;
  final String token;
  final String refresh;
  final DateTime expiresAt;
}
