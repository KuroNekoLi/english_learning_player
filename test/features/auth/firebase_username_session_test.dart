import 'dart:convert';

import 'package:english_learning_player/core/firebase/firebase_endpoint.dart';
import 'package:english_learning_player/features/auth/data/firebase_account_session.dart';
import 'package:english_learning_player/features/auth/social_sign_in.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'username password signs into a distinct reader UID and owner scope',
    () async {
      final http = _FakeFirebaseHttp();
      final session = FirebaseAccountSession(_endpoint, http);

      final uid = await session.signInWithUsername('kuroneko_li', 'dummy-pass');

      expect(uid, 'reader-uid');
      expect(session.uid, 'reader-uid');
      expect(session.cloudUid, 'google-owner-uid');
      expect(session.isReadOnly, isTrue);
      expect(http.lastUri!.path, contains('accounts:signInWithPassword'));
      expect(
        http.lastBody!['email'],
        'kuroneko_li@english-learning-player-auth.firebaseapp.com',
      );
    },
  );

  test(
    'Google owner provisions reader through authenticated callable',
    () async {
      final http = _FakeFirebaseHttp();
      final session = FirebaseAccountSession(_endpoint, http);
      await session.signInWithProvider(
        SocialProvider.google,
        () async => const ProviderIdToken('provider-token'),
      );

      expect(session.uid, 'google-owner-uid');
      expect(session.cloudUid, 'google-owner-uid');
      expect(session.canProvisionReadOnlyLogin, isTrue);
      final readerUid = await session.provisionReadOnlyLogin(
        username: 'kuroneko_li',
        password: 'dummy-test-password',
      );

      expect(readerUid, 'reader-uid');
      expect(http.lastUri, _endpoint.readOnlyProvisionFunction);
      expect(http.lastBody, {
        'data': {'username': 'kuroneko_li', 'password': 'dummy-test-password'},
      });
      expect(
        http.lastAuthorization,
        'Bearer ${_jwt({
          'sub': 'google-owner-uid',
          'firebase': {'sign_in_provider': 'google.com'},
        })}',
      );
      expect(
        session.uid,
        'google-owner-uid',
        reason: 'provisioning preserves owner session',
      );
    },
  );

  test('password identity without server claim is not read-only', () async {
    final session = FirebaseAccountSession(_endpoint, _FakeFirebaseHttp());
    await session.signIn('test@example.com', 'dummy-test-password');
    expect(session.isReadOnly, isFalse);
    expect(session.cloudUid, 'email-user-uid');
    expect(session.canProvisionReadOnlyLogin, isFalse);
  });
}

final _endpoint = FirebaseEndpoint(
  project: 'english-learning-player-auth',
  apiKey: 'test-key',
);

String _jwt(Map<String, Object?> claims) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.signature';

final class _FakeFirebaseHttp implements FirebaseHttp {
  Uri? lastUri;
  Map<String, dynamic>? lastBody;
  String? lastAuthorization;

  @override
  Future<FirebaseResponse> send(
    String method,
    Uri uri, {
    Future<String> Function()? authorization,
    String? contentType,
    Map<String, String> headers = const {},
    List<int>? bytes,
    Stream<List<int>>? body,
    int? length,
  }) async {
    lastUri = uri;
    lastAuthorization = await authorization?.call();
    lastBody = bytes == null
        ? null
        : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final response = uri.path.endsWith('provisionReadOnlyLogin')
        ? {
            'result': {'readerUid': 'reader-uid'},
          }
        : uri.path.endsWith('accounts:signInWithIdp')
        ? {
            'localId': 'google-owner-uid',
            'idToken': _jwt({
              'sub': 'google-owner-uid',
              'firebase': {'sign_in_provider': 'google.com'},
            }),
            'refreshToken': 'owner-refresh-token',
            'expiresIn': '3600',
          }
        : uri.path.endsWith('accounts:signInWithPassword') &&
              lastBody?['email'] ==
                  'kuroneko_li@english-learning-player-auth.firebaseapp.com'
        ? {
            'localId': 'reader-uid',
            'idToken': _jwt({
              'sub': 'reader-uid',
              'elpReadOnlyOwnerUid': 'google-owner-uid',
              'firebase': {'sign_in_provider': 'password'},
            }),
            'refreshToken': 'refresh-token',
            'expiresIn': '3600',
          }
        : {
            'localId': 'email-user-uid',
            'idToken': _jwt({
              'sub': 'email-user-uid',
              'firebase': {'sign_in_provider': 'password'},
            }),
            'refreshToken': 'refresh-token',
            'expiresIn': '3600',
          };
    return FirebaseResponse(
      200,
      Stream.value(utf8.encode(jsonEncode(response))),
    );
  }

  @override
  void close() {}

  @override
  Stream<List<int>> read(FirebaseResponse response) => response.body;

  @override
  Future<Map<String, dynamic>> json(FirebaseResponse response) async =>
      jsonDecode(await utf8.decoder.bind(response.body).join())
          as Map<String, dynamic>;

  @override
  Future<void> requireSuccess(FirebaseResponse response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Unexpected fake HTTP status ${response.statusCode}.');
    }
  }
}
