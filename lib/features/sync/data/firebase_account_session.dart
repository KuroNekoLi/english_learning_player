import 'dart:convert';
import 'dart:io';

import '../../../core/sync/sync_contracts.dart';
import 'firebase_endpoint.dart';

/// The development sign-in holds credentials only in process memory.
final class FirebaseAccountSession implements SyncIdentityProvider {
  FirebaseAccountSession(this.endpoint, this.http);

  final FirebaseEndpoint endpoint;
  final FirebaseHttp http;
  _Credentials? _credentials;
  Future<_Credentials>? _renewing;
  int _generation = 0;

  String? get uid => _credentials?.uid;

  @override
  Future<SyncIdentity?> currentIdentity() async =>
      uid == null ? null : SyncIdentity(uid!);

  Future<String> signIn(String email, String password) async {
    final generation = ++_generation;
    _credentials = null;
    _renewing = null;
    final response = await http.send(
      'POST',
      endpoint.auth('signInWithPassword'),
      contentType: ContentType.json,
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
    return credentials.uid;
  }

  void signOut() {
    _generation++;
    _credentials = null;
    _renewing = null;
  }

  Future<String> tokenFor(String expectedUid) async {
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
      contentType: ContentType('application', 'x-www-form-urlencoded'),
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
}

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
        uid.isEmpty ||
        uid.contains('/') ||
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
