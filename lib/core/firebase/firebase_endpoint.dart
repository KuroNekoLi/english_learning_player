export 'firebase_http.dart';

final class FirebaseEndpoint {
  FirebaseEndpoint({
    required this.project,
    required this.apiKey,
    this.bucket,
    this.emulatorHost,
    this.progressRegion,
  }) {
    final demo = emulatorHost != null;
    if (!RegExp(r'^[a-z][a-z0-9-]+$').hasMatch(project) ||
        (bucket != null &&
            !RegExp(r'^[a-z0-9][a-z0-9.-]+$').hasMatch(bucket!)) ||
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
      bucket: host.isEmpty
          ? (bucket.isEmpty ? null : bucket)
          : '$project.appspot.com',
      apiKey: host.isEmpty ? key : 'demo-key',
      emulatorHost: host.isEmpty ? null : host,
      progressRegion: region.isNotEmpty
          ? region
          : (host.isEmpty ? null : 'us-central1'),
    );
  }

  final String project;
  final String? bucket;
  final String apiKey;
  final String? emulatorHost;
  final String? progressRegion;

  bool get isEmulator => emulatorHost != null;
  bool get isMediaSyncConfigured => bucket != null;

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

  Uri storage({String? object, Map<String, String>? query}) {
    final storageBucket = bucket;
    if (storageBucket == null) {
      throw StateError('Firebase Storage is not configured.');
    }
    return _uri('firebasestorage.googleapis.com', 9199, [
      'v0',
      'b',
      storageBucket,
      'o',
      ?object,
    ], query);
  }

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
    final parts = host.split('.');
    if (parts.length != 4 ||
        parts.any((p) => !RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(p))) {
      return false;
    }
    final bytes = parts.map(int.parse).toList();
    if (bytes.any((byte) => byte > 255)) return false;
    final a = bytes[0];
    final b = bytes[1];
    return a == 127 ||
        a == 10 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }
}
