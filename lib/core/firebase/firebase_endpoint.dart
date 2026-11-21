import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../sync/sync_contracts.dart';

final class FirebaseEndpoint {
  FirebaseEndpoint({
    required this.project,
    required this.bucket,
    required this.apiKey,
    this.emulatorHost,
    this.progressRegion,
  }) {
    final demo = emulatorHost != null;
    if (!RegExp(r'^[a-z][a-z0-9-]+$').hasMatch(project) ||
        !RegExp(r'^[a-z0-9][a-z0-9.-]+$').hasMatch(bucket) ||
        apiKey.trim().isEmpty ||
        (progressRegion != null &&
            !RegExp(r'^[a-z]+-[a-z]+[0-9]+$').hasMatch(progressRegion!)) ||
        demo != project.startsWith('demo-') ||
        (demo &&
            (bucket != '$project.appspot.com' ||
                !_isLocalHost(emulatorHost!)))) {
      throw const FormatException('Invalid Firebase configuration.');
    }
  }

  static FirebaseEndpoint? fromEnvironment() {
    const project = String.fromEnvironment('ELP_FIREBASE_PROJECT');
    if (project.isEmpty) return null;
    const host = String.fromEnvironment('ELP_FIREBASE_EMULATOR_HOST');
    const key = String.fromEnvironment('ELP_FIREBASE_API_KEY');
    const bucket = String.fromEnvironment('ELP_FIREBASE_BUCKET');
    const region = String.fromEnvironment('ELP_FIREBASE_PROGRESS_REGION');
    return FirebaseEndpoint(
      project: project,
      bucket: host.isEmpty ? bucket : '$project.appspot.com',
      apiKey: host.isEmpty ? key : 'demo-key',
      emulatorHost: host.isEmpty ? null : host,
      progressRegion: region.isNotEmpty
          ? region
          : (host.isEmpty ? null : 'us-central1'),
    );
  }

  final String project;
  final String bucket;
  final String apiKey;
  final String? emulatorHost;
  final String? progressRegion;

  bool get isEmulator => emulatorHost != null;

  Uri auth(String method) => _uri(
    'identitytoolkit.googleapis.com',
    9099,
    [
      if (isEmulator) 'identitytoolkit.googleapis.com',
      'v1',
      'accounts:$method',
    ],
    {'key': apiKey},
  );

  Uri get refresh => _uri(
    'securetoken.googleapis.com',
    9099,
    [if (isEmulator) 'securetoken.googleapis.com', 'v1', 'token'],
    {'key': apiKey},
  );

  Uri get progressFunction {
    final region = progressRegion;
    if (region == null) {
      throw StateError('The progress region is not configured.');
    }
    return _uri('$region-$project.cloudfunctions.net', 5001, [
      if (isEmulator) ...[project, region],
      'syncProgress',
    ], null);
  }

  Uri firestore(List<String> path, [Map<String, String>? query]) => _uri(
    'firestore.googleapis.com',
    8080,
    ['v1', 'projects', project, 'databases', '(default)', 'documents', ...path],
    query,
  );

  Uri storage({String? object, Map<String, String>? query}) => _uri(
    'firebasestorage.googleapis.com',
    9199,
    ['v0', 'b', bucket, 'o', if (object != null) object],
    query,
  );

  Uri _uri(
    String host,
    int port,
    List<String> path,
    Map<String, String>? query,
  ) => Uri(
    scheme: isEmulator ? 'http' : 'https',
    host: emulatorHost ?? host,
    port: isEmulator ? port : null,
    pathSegments: path,
    queryParameters: query,
  );

  static bool _isLocalHost(String host) {
    if (host == 'localhost') return true;
    final bytes = InternetAddress.tryParse(host)?.rawAddress;
    if (bytes == null || bytes.length != 4) return false;
    final a = bytes[0];
    final b = bytes[1];
    return a == 127 ||
        a == 10 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }
}

final class FirebaseHttp {
  FirebaseHttp() {
    _client.connectionTimeout = const Duration(seconds: 15);
  }

  final HttpClient _client = HttpClient();

  Future<HttpClientResponse> send(
    String method,
    Uri uri, {
    String? authorization,
    ContentType? contentType,
    Map<String, String> headers = const {},
    List<int>? bytes,
    Stream<List<int>>? body,
    int? length,
  }) async {
    HttpClientRequest? request;
    try {
      final outgoing = request = await _client.openUrl(method, uri);
      outgoing.followRedirects = false;
      if (authorization != null) {
        outgoing.headers.set(HttpHeaders.authorizationHeader, authorization);
      }
      if (contentType != null) outgoing.headers.contentType = contentType;
      headers.forEach(outgoing.headers.set);
      if (length != null) outgoing.contentLength = length;
      if (bytes != null) outgoing.add(bytes);
      if (body != null) {
        await outgoing.addStream(body).timeout(const Duration(minutes: 3));
      }
      return await outgoing.close().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      request?.abort();
      throw const SyncFailure(SyncFailureKind.transient, 'network_timeout');
    } on IOException {
      request?.abort();
      throw const SyncFailure(SyncFailureKind.transient, 'network_unavailable');
    }
  }

  Future<Map<String, dynamic>> json(HttpClientResponse response) async {
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

  Stream<List<int>> read(HttpClientResponse response) async* {
    try {
      yield* response.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const SyncFailure(SyncFailureKind.transient, 'network_timeout');
    } on IOException {
      throw const SyncFailure(SyncFailureKind.transient, 'network_unavailable');
    }
  }

  Future<void> requireSuccess(HttpClientResponse response) async {
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

  void close() => _client.close(force: true);
}
