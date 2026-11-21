import 'dart:convert';

import '../sync/sync_contracts.dart';
import 'firebase_http_native.dart'
    if (dart.library.js_interop) 'firebase_http_web.dart'
    as platform;

final class FirebaseResponse {
  const FirebaseResponse(this.statusCode, this.body);
  final int statusCode;
  final Stream<List<int>> body;
}

abstract class FirebaseHttp {
  factory FirebaseHttp() => platform.createFirebaseHttp();
  FirebaseHttp.platform();

  Future<FirebaseResponse> send(
    String method,
    Uri uri, {
    Future<String> Function()? authorization,
    String? contentType,
    Map<String, String> headers = const {},
    List<int>? bytes,
    Stream<List<int>>? body,
    int? length,
  });

  Stream<List<int>> read(FirebaseResponse response) => response.body;

  Future<Map<String, dynamic>> json(FirebaseResponse response) async {
    try {
      final data = await utf8.decoder.bind(read(response)).join();
      return jsonDecode(data) as Map<String, dynamic>;
    } on FormatException {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'invalid_firebase_response',
      );
    } on TypeError {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'invalid_firebase_response',
      );
    }
  }

  Future<void> requireSuccess(FirebaseResponse response) async {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;
    await read(response).drain<void>();
    throw SyncFailure(switch (code) {
      401 => SyncFailureKind.unauthenticated,
      403 => SyncFailureKind.permissionDenied,
      408 || 409 || 429 => SyncFailureKind.transient,
      >= 500 => SyncFailureKind.transient,
      _ => SyncFailureKind.invalidData,
    }, 'firebase_http_$code');
  }

  static List<int> encode(Object data) => utf8.encode(jsonEncode(data));

  void close();
}
