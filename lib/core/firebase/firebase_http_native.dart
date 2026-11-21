import 'dart:async';
import 'dart:io';

import '../sync/sync_contracts.dart';
import 'firebase_http.dart';

FirebaseHttp createFirebaseHttp() => NativeFirebaseHttp();

final class NativeFirebaseHttp extends FirebaseHttp {
  NativeFirebaseHttp() : super.platform() {
    _client.connectionTimeout = const Duration(seconds: 15);
  }

  final HttpClient _client = HttpClient();

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
    HttpClientRequest? request;
    try {
      final authorizationHeader = await authorization?.call();
      final outgoing = request = await _client.openUrl(method, uri);
      outgoing.followRedirects = false;
      if (authorizationHeader != null) {
        outgoing.headers.set(
          HttpHeaders.authorizationHeader,
          authorizationHeader,
        );
      }
      if (contentType != null) {
        outgoing.headers.set('Content-Type', contentType);
      }
      headers.forEach(outgoing.headers.set);
      if (length != null) outgoing.contentLength = length;
      if (bytes != null) outgoing.add(bytes);
      if (body != null) {
        await outgoing.addStream(body).timeout(const Duration(minutes: 3));
      }
      final response = await outgoing.close().timeout(
        const Duration(seconds: 30),
      );
      return FirebaseResponse(response.statusCode, _read(response));
    } on TimeoutException {
      request?.abort();
      throw const SyncFailure(SyncFailureKind.transient, 'network_timeout');
    } on IOException {
      request?.abort();
      throw const SyncFailure(SyncFailureKind.transient, 'network_unavailable');
    } catch (_) {
      request?.abort();
      rethrow;
    }
  }

  Stream<List<int>> _read(HttpClientResponse response) async* {
    try {
      yield* response.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const SyncFailure(SyncFailureKind.transient, 'network_timeout');
    } on IOException {
      throw const SyncFailure(SyncFailureKind.transient, 'network_unavailable');
    }
  }

  @override
  void close() => _client.close(force: true);
}
