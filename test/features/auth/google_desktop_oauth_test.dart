import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:english_learning_player/features/auth/google_desktop_oauth.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> returnToLocalhost(
  Uri url, {
  String? error,
  bool badState = false,
}) async {
  final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
  final callback = redirect.replace(
    queryParameters: {
      'state': badState ? 'wrong-state' : url.queryParameters['state']!,
      if (error == null) 'code': 'authorization-code',
      if (error != null) 'error': error,
    },
  );
  final http = HttpClient();
  try {
    final response = await (await http.getUrl(callback)).close();
    final status = response.statusCode;
    await response.drain<void>();
    return status;
  } finally {
    http.close(force: true);
  }
}

void main() {
  test('RFC 7636 S256 verifier produces expected challenge', () {
    expect(
      GoogleDesktopOAuth.codeChallenge(
        'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
      ),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('authorization URI uses desktop client, loopback, state and PKCE', () {
    final auth = GoogleDesktopOAuth(clientId: 'desktop-client');
    final url = auth.authorizationUri(
      redirectUri: Uri.parse('http://127.0.0.1:1234/oauth2callback'),
      state: 'random-state',
      codeVerifier: 'verifier',
    );
    expect(url.host, 'accounts.google.com');
    expect(url.queryParameters['client_id'], 'desktop-client');
    expect(url.queryParameters['response_type'], 'code');
    expect(url.queryParameters['scope'], contains('openid'));
    expect(url.queryParameters['state'], 'random-state');
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(
      url.queryParameters['redirect_uri'],
      'http://127.0.0.1:1234/oauth2callback',
    );
  });

  test('valid OAuth callback exchanges code without leaking to logs', () async {
    final tokenServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => tokenServer.close(force: true));
    final received = Completer<Map<String, String>>();
    tokenServer.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.complete(Uri.splitQueryString(body));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'id_token': 'fixture-id-token'}));
      await request.response.close();
    });
    final auth = GoogleDesktopOAuth(
      clientId: 'desktop-client',
      tokenEndpoint: Uri.parse('http://127.0.0.1:${tokenServer.port}/token'),
      openBrowser: (url) async {
        expect(await returnToLocalhost(url, badState: true), 400);
        expect(await returnToLocalhost(url), 200);
        return true;
      },
    );
    expect(await auth.authenticate(), 'fixture-id-token');
    final params = await received.future;
    expect(params['client_id'], 'desktop-client');
    expect(params['code'], 'authorization-code');
    expect(params['code_verifier'], hasLength(43));
    expect(params['grant_type'], 'authorization_code');
    expect(params['redirect_uri'], startsWith('http://127.0.0.1:'));
  });

  test('cancellation keeps the caller signed out', () async {
    final auth = GoogleDesktopOAuth(
      clientId: 'desktop-client',
      openBrowser: (url) async {
        expect(await returnToLocalhost(url, error: 'access_denied'), 200);
        return true;
      },
    );
    expect(await auth.authenticate(), isNull);
  });

  test('browser failure cleans up localhost listener', () async {
    final auth = GoogleDesktopOAuth(
      clientId: 'desktop-client',
      openBrowser: (_) async => false,
    );
    await expectLater(auth.authenticate(), throwsStateError);
  });
}
