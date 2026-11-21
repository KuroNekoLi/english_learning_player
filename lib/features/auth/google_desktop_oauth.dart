import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google's installed desktop application flow: system browser + loopback + PKCE.
/// Does not depend on macOS keychain sharing or an Apple signing team.
final class GoogleDesktopOAuth {
  GoogleDesktopOAuth({
    required this.clientId,
    this.clientSecret = '',
    Future<bool> Function(Uri)? openBrowser,
    Uri? tokenEndpoint,
    this.timeout = const Duration(minutes: 5),
  }) : _openBrowser = openBrowser ?? _launch,
       _tokenEndpoint =
           tokenEndpoint ?? Uri.https('oauth2.googleapis.com', '/token');

  final String clientId;
  final String clientSecret;
  final Future<bool> Function(Uri) _openBrowser;
  final Uri _tokenEndpoint;
  final Duration timeout;

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static String _random() => base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  static String codeChallenge(String verifier) => base64UrlEncode(
    sha256.convert(ascii.encode(verifier)).bytes,
  ).replaceAll('=', '');

  Uri authorizationUri({
    required Uri redirectUri,
    required String state,
    required String codeVerifier,
  }) => Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
    'client_id': clientId,
    'redirect_uri': redirectUri.toString(),
    'response_type': 'code',
    'scope': 'openid email profile',
    'state': state,
    'code_challenge': codeChallenge(codeVerifier),
    'code_challenge_method': 'S256',
    'prompt': 'select_account',
  });

  Future<String?> authenticate() async {
    if (clientId.isEmpty) throw StateError('Desktop OAuth client is missing.');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final callback = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/oauth2callback',
    );
    final verifier = _random();
    final state = _random();
    final codeResult = Completer<String?>();
    final subscription = server.listen((request) async {
      if (request.uri.path != callback.path ||
          request.uri.queryParameters['state'] != state) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      final error = request.uri.queryParameters['error'];
      final code = request.uri.queryParameters['code'];
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><title>English Learning Player</title>'
        '<p>Return to the app. You can close this tab.</p>',
      );
      await request.response.close();
      if (codeResult.isCompleted) return;
      if (error == 'access_denied') {
        codeResult.complete(null);
      } else if (error != null || code == null || code.isEmpty) {
        codeResult.completeError(StateError('Google authorization failed.'));
      } else {
        codeResult.complete(code);
      }
    });
    try {
      final opened = await _openBrowser(
        authorizationUri(
          redirectUri: callback,
          state: state,
          codeVerifier: verifier,
        ),
      );
      if (!opened) throw StateError('Could not open the system browser.');
      final code = await codeResult.future.timeout(timeout);
      if (code == null) return null;
      return _exchange(code: code, redirectUri: callback, verifier: verifier);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<String> _exchange({
    required String code,
    required Uri redirectUri,
    required String verifier,
  }) async {
    final http = HttpClient();
    try {
      final request = await http.postUrl(_tokenEndpoint);
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(
        Uri(
          queryParameters: {
            'client_id': clientId,
            if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
            'code': code,
            'code_verifier': verifier,
            'redirect_uri': redirectUri.toString(),
            'grant_type': 'authorization_code',
          },
        ).query,
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'Google token exchange failed: HTTP ${response.statusCode}.',
        );
      }
      final data = jsonDecode(body);
      if (data is! Map ||
          data['id_token'] is! String ||
          (data['id_token'] as String).isEmpty) {
        throw StateError('Google did not return an ID token.');
      }
      return data['id_token'] as String;
    } finally {
      http.close(force: true);
    }
  }
}
