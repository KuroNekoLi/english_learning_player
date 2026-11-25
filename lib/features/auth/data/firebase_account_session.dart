import 'dart:convert';

import '../../../core/sync/sync_contracts.dart';
import '../social_sign_in.dart';
import '../../../core/firebase/firebase_endpoint.dart';
import 'firebase_credential_store.dart';
import 'firebase_identity_session.dart';
import '../username_login.dart';

/// The active account used by all Firebase synchronization transports.
final class FirebaseAccountSession implements FirebaseIdentitySession {
  FirebaseAccountSession(this.endpoint, this.http, {this.credentialStore});

  final FirebaseEndpoint endpoint;
  final FirebaseHttp http;
  final FirebaseCredentialStore? credentialStore;
  _Credentials? _credentials;
  NativeFirebaseUser? _nativeUser;
  bool _readOnly = false;
  Future<_Credentials>? _renewing;
  int _generation = 0;

  @override
  String? get uid => _credentials?.uid ?? _nativeUser?.uid;

  @override
  String? get cloudUid =>
      _credentials?.readOnlyOwnerUid ?? _nativeUser?.uid ?? _credentials?.uid;

  /// Password credentials are intentionally read-only in Firebase Rules.
  @override
  bool get isReadOnly => _readOnly;

  bool get canProvisionReadOnlyLogin =>
      _credentials?.signInProvider == 'google.com' && !_readOnly;

  SocialProvider? get signedInProvider =>
      switch (_credentials?.signInProvider ??
      (_nativeUser == null ? null : 'apple.com')) {
        'google.com' => SocialProvider.google,
        'apple.com' => SocialProvider.apple,
        _ => null,
      };

  @override
  Future<SyncIdentity?> currentIdentity() async =>
      uid == null ? null : SyncIdentity(uid!);

  /// Restores only credentials previously saved to the injected secure store.
  /// Refreshing an expired token remains lazy so startup works offline.
  Future<String?> restore({NativeFirebaseUser? nativeUser}) async {
    if (nativeUser != null && _validUid(nativeUser.uid)) {
      _nativeUser = nativeUser;
      _credentials = null;
      _readOnly = false;
      await credentialStore?.clear();
      return nativeUser.uid;
    }
    final stored = await credentialStore?.read();
    if (stored == null || stored.isEmpty) return null;
    try {
      final credentials = _Credentials.fromStored(jsonDecode(stored));
      _credentials = credentials;
      _readOnly = credentials.readOnlyOwnerUid != null;
      return credentials.uid;
    } on FormatException {
      await credentialStore?.clear();
      return null;
    } on TypeError {
      await credentialStore?.clear();
      return null;
    }
  }

  Future<String> signIn(String email, String password) async {
    await signOut();
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
    await _persistCredentials(credentials, generation);
    _credentials = credentials;
    _readOnly = credentials.readOnlyOwnerUid != null;
    return credentials.uid;
  }

  Future<String> signInWithUsername(String username, String password) {
    final normalized = normalizeLoginUsername(username);
    if (!isReadOnlyLoginUsername(normalized) ||
        !isSupportedReadOnlyLoginProject(endpoint.project)) {
      throw const SyncFailure(SyncFailureKind.invalidData, 'invalid_username');
    }
    return signIn(loginEmail(normalized, endpoint.project), password);
  }

  /// Provisions an independent reader UID from the authenticated owner session.
  Future<String> provisionReadOnlyLogin({
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
    if (password.length < 6) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'password_too_short',
      );
    }
    final current = _credentials;
    if (current == null || !canProvisionReadOnlyLogin) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'google_owner_session_required',
      );
    }
    final generation = _generation;
    final token = await tokenFor(current.uid);
    final response = await http.send(
      'POST',
      endpoint.readOnlyProvisionFunction,
      contentType: 'application/json',
      bytes: FirebaseHttp.encode({
        'data': {'username': normalized, 'password': password},
      }),
      authorization: () async => 'Bearer $token',
    );
    if (response.statusCode == 400) {
      await http.json(response);
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'readonly_login_provision_rejected',
      );
    }
    await http.requireSuccess(response);
    final payload = await http.json(response);
    final result = payload['result'] ?? payload['data'];
    final readerUid = result is Map ? result['readerUid'] : null;
    if (_generation != generation ||
        readerUid is! String ||
        readerUid.isEmpty) {
      _notSignedIn();
    }
    return readerUid;
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
        await credentialStore?.clear();
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
        await _persistCredentials(credentials, generation);
        _credentials = credentials;
        _readOnly = false;
        return credentials.uid;
    }
  }

  Future<void> signOut() async {
    _generation++;
    _credentials = null;
    _nativeUser = null;
    _readOnly = false;
    _renewing = null;
    await credentialStore?.clear();
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
      await _persistCredentials(updated, generation);
      _credentials = updated;
      return updated.token;
    } finally {
      if (identical(_renewing, renew)) _renewing = null;
    }
  }

  Future<void> _persistCredentials(
    _Credentials credentials,
    int generation,
  ) async {
    await credentialStore?.write(jsonEncode(credentials.toStored()));
    if (_generation != generation) {
      await credentialStore?.clear();
      _notSignedIn();
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
      await credentialStore?.clear();
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
  const _Credentials(
    this.uid,
    this.token,
    this.refresh,
    this.expiresAt,
    this.readOnlyOwnerUid,
    this.signInProvider,
  );

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
    final claims = _decodeJwtClaims(token is String ? token : '');
    final ownerClaim = claims['elpReadOnlyOwnerUid'];
    final firebaseClaim = claims['firebase'];
    final signInProvider = firebaseClaim is Map
        ? firebaseClaim['sign_in_provider']
        : null;
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
      ownerClaim is String && _validUid(ownerClaim) ? ownerClaim : null,
      signInProvider is String ? signInProvider : null,
    );
  }

  factory _Credentials.fromStored(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid stored Firebase session.');
    }
    final uid = value['uid'];
    final token = value['token'];
    final refresh = value['refresh'];
    final expiresAtMs = value['expiresAtMs'];
    final ownerUid = value['readOnlyOwnerUid'];
    final provider = value['signInProvider'];
    if (uid is! String ||
        !_validUid(uid) ||
        token is! String ||
        token.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        expiresAtMs is! int ||
        (ownerUid != null && (ownerUid is! String || !_validUid(ownerUid))) ||
        (provider != null && provider is! String)) {
      throw const FormatException('Invalid stored Firebase session.');
    }
    return _Credentials(
      uid,
      token,
      refresh,
      DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
      ownerUid as String?,
      provider as String?,
    );
  }

  Map<String, Object?> toStored() => {
    'uid': uid,
    'token': token,
    'refresh': refresh,
    'expiresAtMs': expiresAt.millisecondsSinceEpoch,
    'readOnlyOwnerUid': readOnlyOwnerUid,
    'signInProvider': signInProvider,
  };

  final String uid;
  final String token;
  final String refresh;
  final DateTime expiresAt;
  final String? readOnlyOwnerUid;
  final String? signInProvider;
}

Map<String, dynamic> _decodeJwtClaims(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return const {};
  try {
    return jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}
