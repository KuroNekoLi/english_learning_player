import 'dart:convert';

import 'package:english_learning_player/core/firebase/firebase_endpoint.dart';
import 'package:english_learning_player/features/auth/data/firebase_account_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'username password sign-in maps alias and enters read-only mode',
    () async {
      final http = _FakeFirebaseHttp();
      final session = FirebaseAccountSession(_endpoint, http);

      final uid = await session.signInWithUsername('kuroneko_li', 'secret');

      expect(uid, 'shared-google-uid');
      expect(session.isReadOnly, isTrue);
      expect(http.lastUri!.path, contains('accounts:signInWithPassword'));
      expect(
        http.lastBody!['email'],
        'kuroneko_li@english-learning-player-auth.firebaseapp.com',
      );
      expect(http.lastBody!['password'], 'secret');
    },
  );

  test('ordinary email password session remains writable', () async {
    final session = FirebaseAccountSession(_endpoint, _FakeFirebaseHttp());
    await session.signIn('test@example.com', 'test-password');
    expect(session.isReadOnly, isFalse);
  });

  test(
    'Google owner can link the read-only alias without changing UID',
    () async {
      final http = _FakeFirebaseHttp();
      final session = FirebaseAccountSession(_endpoint, http);
      final uid = await session.signIn(
        'google-owner@example.com',
        'owner-token',
      );

      await session.linkReadOnlyUsername(
        username: 'kuroneko_li',
        password: 'a-long-unique-password',
      );

      expect(http.lastUri!.path, contains('accounts:update'));
      expect(http.lastBody!['idToken'], 'firebase-id-token');
      expect(
        http.lastBody!['email'],
        'kuroneko_li@english-learning-player-auth.firebaseapp.com',
      );
      expect(http.lastBody!['password'], 'a-long-unique-password');
      expect(
        session.uid,
        isNull,
        reason: 'linking requires a fresh owner sign-in',
      );
      expect(uid, 'shared-google-uid');
    },
  );
}

final _endpoint = FirebaseEndpoint(
  project: 'english-learning-player-auth',
  apiKey: 'test-key',
);

final class _FakeFirebaseHttp implements FirebaseHttp {
  Uri? lastUri;
  Map<String, dynamic>? lastBody;
  String method = '';

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
    this.method = method;
    lastUri = uri;
    lastBody = bytes == null
        ? null
        : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final isUpdate = uri.path.endsWith('accounts:update');
    return FirebaseResponse(
      200,
      Stream.value(
        utf8.encode(
          jsonEncode({
            'localId': 'shared-google-uid',
            'idToken': 'firebase-id-token',
            'refreshToken': 'firebase-refresh-token',
            'expiresIn': '3600',
            if (isUpdate)
              'email':
                  'kuroneko_li@english-learning-player-auth.firebaseapp.com',
          }),
        ),
      ),
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
