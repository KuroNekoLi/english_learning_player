import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/sync_contracts.dart';
import '../../library/material_repository.dart';
import '../../subtitles/domain/srt_parser.dart';
import '../../subtitles/domain/subtitle_models.dart';
import 'firebase_material_transport.dart';

/// The origin device publishes selected tracks; receiving devices cache copies.
final class FirebaseSubtitleSync {
  const FirebaseSubtitleSync({
    required this.uid,
    required this.transport,
    required this.repository,
    required this.consent,
  });

  static const maxBytes = 2 * 1024 * 1024;
  final String uid;
  final FirebaseMaterialTransport transport;
  final MaterialRepository repository;
  final SyncConsentProvider consent;

  List<String> _collection(String materialId) => [
    'users',
    uid,
    'materials',
    materialId,
    'subtitleTracks',
  ];

  String _object(String materialId, String digest) =>
      'users/$uid/subtitles/$materialId/$digest';

  Future<void> publish(String materialId) async {
    await _checkConsent();
    final tracks = await repository.listSubtitleTracks(materialId);
    for (final track in tracks.where((item) => item.isSelected)) {
      final language = track.languageTag.toLowerCase();
      if (!RegExp(r'^(en|zh)(?:-[a-z0-9]{2,8})*$').hasMatch(language)) continue;
      final key = language.substring(0, 2);
      final bytes = track.originalBytes;
      if (bytes.isEmpty || bytes.length > maxBytes) _invalid();
      final digest = sha256.convert(bytes).toString();
      final object = _object(materialId, digest);
      final manifestPath = [..._collection(materialId), key];
      final manifest = {
        'schemaVersion': 1,
        'ownerId': uid,
        'materialId': materialId,
        'languageTag': language,
        'sha256': digest,
        'byteLength': bytes.length,
        'revision': track.revision,
        'offsetMs': track.offsetMs,
        'storagePath': object,
      };
      final existing = await transport.readDocument(uid, manifestPath);
      if (existing != null &&
          manifest.entries.every(
            (field) => existing[field.key] == field.value,
          )) {
        continue;
      }
      await _checkConsent();
      await transport.putSubtitleObject(
        uid: uid,
        path: object,
        bytes: bytes,
        digest: digest,
      );
      await _verifiedRead(object, digest, bytes.length);
      await _checkConsent();
      await transport.writeDocument(uid, manifestPath, manifest);
    }
  }

  Future<void> download(String materialId) async {
    await _checkConsent();
    final manifests = await transport.listDocuments(
      uid,
      _collection(materialId),
    );
    final tracks = await repository.listSubtitleTracks(materialId);
    for (final manifest in manifests) {
      final language = manifest['languageTag'];
      final digest = manifest['sha256'];
      final size = manifest['byteLength'];
      final revision = manifest['revision'];
      final offsetMs = manifest['offsetMs'];
      if (manifest['schemaVersion'] != 1 ||
          manifest['ownerId'] != uid ||
          manifest['materialId'] != materialId ||
          language is! String ||
          !RegExp(r'^(en|zh)(?:-[a-z0-9]{2,8})*$').hasMatch(language) ||
          digest is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
          manifest['storagePath'] != _object(materialId, digest) ||
          size is! int ||
          size <= 0 ||
          size > maxBytes ||
          revision is! int ||
          revision <= 0 ||
          offsetMs is! int) {
        _invalid();
      }
      final id = const Uuid().v5(
        Namespace.url.value,
        'firebase-subtitle:$uid/$materialId/$language/$digest/$revision/$offsetMs',
      );
      if (tracks.any((track) => track.id == id && track.isSelected)) continue;
      final bytes = await _verifiedRead(
        _object(materialId, digest),
        digest,
        size,
      );
      final parsed = const SrtParser().parse(bytes);
      if (parsed.cues.isEmpty) _invalid();
      await _checkConsent();
      await repository.saveSubtitleTrack(
        SubtitleTrack(
          id: id,
          ownerId: uid,
          materialId: materialId,
          languageTag: language,
          sourceName: 'cloud-$language.srt',
          originalBytes: bytes,
          revision: revision,
          offsetMs: offsetMs,
          selectionMode: SubtitleSelectionMode.automatic,
          isSelected: false,
          cues: parsed.cues,
        ),
        manual: false,
      );
    }
  }

  Future<Uint8List> _verifiedRead(
    String object,
    String digest,
    int size,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in transport.readObject(uid, object)) {
      if (builder.length + chunk.length > size) _invalid();
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.length != size || sha256.convert(bytes).toString() != digest) {
      _invalid();
    }
    return bytes;
  }

  Future<void> _checkConsent() async {
    if (!await consent.isCloudSyncEnabled(uid)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'consent_required',
      );
    }
  }

  static Never _invalid() => throw const SyncFailure(
    SyncFailureKind.invalidData,
    'invalid_cloud_subtitle',
  );
}
