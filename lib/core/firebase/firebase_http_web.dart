import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../files/media_store.dart';
import '../sync/sync_contracts.dart';
import 'firebase_http.dart';

FirebaseHttp createFirebaseHttp() => BrowserFirebaseHttp();

final class BrowserFirebaseHttp extends FirebaseHttp {
  BrowserFirebaseHttp() : super.platform();

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
    final requestHeaders = web.Headers();
    headers.forEach((name, value) => requestHeaders.set(name, value));
    if (contentType != null) requestHeaders.set('Content-Type', contentType);

    final abort = web.AbortController();
    try {
      final payload = body == null
          ? (bytes == null ? null : Uint8List.fromList(bytes).toJS)
          : await _multipart(body, length);
      final authorizationHeader = await authorization?.call();
      if (authorizationHeader != null) {
        requestHeaders.set('Authorization', authorizationHeader);
      }
      final response = await web.window
          .fetch(
            uri.toString().toJS,
            web.RequestInit(
              method: method,
              headers: requestHeaders,
              body: payload,
              credentials: 'omit',
              redirect: 'error',
              signal: abort.signal,
            ),
          )
          .toDart
          .timeout(const Duration(minutes: 3));
      final stream = response.body;
      return FirebaseResponse(
        response.status,
        stream == null ? const Stream.empty() : _read(stream, abort),
      );
    } on SyncFailure {
      rethrow;
    } on AudioImportException {
      rethrow;
    } on TimeoutException {
      abort.abort();
      throw const SyncFailure(SyncFailureKind.transient, 'network_timeout');
    } catch (_) {
      abort.abort();
      throw const SyncFailure(SyncFailureKind.transient, 'network_unavailable');
    }
  }

  // Fetch accepts a Blob in browsers that do not support streaming uploads.
  // Only one bounded object is assembled by the foreground sync runner.
  Future<web.Blob> _multipart(Stream<List<int>> body, int? length) async {
    const maxMultipartLength = 100 * 1024 * 1024 + 4096;
    if (length == null || length < 1 || length > maxMultipartLength) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'invalid_upload_size',
      );
    }
    var total = 0;
    final parts = <JSUint8Array>[];
    await for (final chunk in body.timeout(const Duration(seconds: 30))) {
      total += chunk.length;
      if (total > length) break;
      parts.add(Uint8List.fromList(chunk).toJS);
    }
    if (total != length) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'invalid_upload_size',
      );
    }
    return web.Blob(parts.toJS);
  }

  Stream<List<int>> _read(
    web.ReadableStream stream,
    web.AbortController abort,
  ) async* {
    final reader = web.ReadableStreamDefaultReader(stream);
    var done = false;
    try {
      while (!done) {
        final chunk = await reader.read().toDart.timeout(
          const Duration(seconds: 30),
        );
        done = chunk.done;
        if (!done) yield (chunk.value as JSUint8Array).toDart;
      }
    } on TimeoutException {
      throw const SyncFailure(SyncFailureKind.transient, 'network_timeout');
    } catch (_) {
      throw const SyncFailure(SyncFailureKind.transient, 'network_unavailable');
    } finally {
      if (!done) abort.abort();
      reader.releaseLock();
    }
  }

  @override
  void close() {}
}
