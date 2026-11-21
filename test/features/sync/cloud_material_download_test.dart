import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/core/files/app_media_store.dart';
import 'package:english_learning_player/core/sync/progress_policy.dart';
import 'package:english_learning_player/core/sync/sqlite_sync_outbox.dart';
import 'package:english_learning_player/core/sync/sync_contracts.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/player/services/material_playback_loader.dart';
import 'package:english_learning_player/features/progress/data/sqlite_progress_repository.dart';
import 'package:english_learning_player/features/progress/services/progress_sync_coordinator.dart';
import 'package:english_learning_player/features/sync/services/cloud_material_download_service.dart';
import 'package:english_learning_player/features/sync/services/cloud_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_cloud_sync.dart';
import '../../fakes/fake_progress_ledger.dart';

void main() {
  // The two simulated devices use different files and executors.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final scope = AccountScope('test-owner');
  final bytes = [1, 2, 3, 4];
  late Directory root;
  late AccountDatabaseService receiverFiles;
  late LocalDatabase receiverDb;
  late SqliteMaterialRepository receiver;
  late FakeSyncIdentityProvider session;
  late FakeSyncConsentProvider consent;
  late _DownloadTransport downloadTransport;
  late CloudMaterialDownloadService download;

  CloudMaterialMetadata metadata(String uid) {
    final digest = sha256.convert(bytes);
    return CloudMaterialMetadata(
      materialId: 'lesson',
      title: 'Synthetic lesson',
      assetId: 'asset',
      sha256: digest.toString(),
      byteLength: bytes.length,
      mediaType: 'audio/mp4',
      storagePath: 'users/$uid/assets/asset/$digest',
      opId: 'fixture',
      payloadHash: 'fixture-hash',
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('player-wp14-');
    receiverFiles = AccountDatabaseService(
      supportDirectory: Directory('${root.path}/receiver'),
    );
    receiverDb = await receiverFiles.open(scope);
    receiver = SqliteMaterialRepository(scope: scope, database: receiverDb);
    session = FakeSyncIdentityProvider(SyncIdentity(scope.ownerId));
    consent = FakeSyncConsentProvider();
    downloadTransport = _DownloadTransport(bytes);
    download = CloudMaterialDownloadService(
      scope: scope,
      identityProvider: session,
      consentProvider: consent,
      transport: downloadTransport,
      repository: receiver,
      mediaStore: AppMediaStore(storage: receiverFiles, scope: scope),
    );
  });

  tearDown(() async {
    await receiverDb.close();
    await root.delete(recursive: true);
  });

  test(
    'uploaded material opens in the second profile with the same confirmed progress',
    () async {
      final sourceFiles = AccountDatabaseService(
        supportDirectory: Directory('${root.path}/mac'),
      );
      final sourceDb = await sourceFiles.open(scope);
      addTearDown(sourceDb.close);
      final source = SqliteMaterialRepository(scope: scope, database: sourceDb);
      final material =
          (await AudioImportService(
                repository: source,
                mediaStore: AppMediaStore(storage: sourceFiles, scope: scope),
              ).importAudio(
                AudioImportSource(
                  sourceKey: 'synthetic-source',
                  name: 'lesson.m4a',
                  openRead: () => Stream.value(bytes),
                ),
              ))
              .material;
      final upload = FakeCloudSyncTransport();
      upload.afterUpload = () async {
        final asset = (await source.audioAssetForMaterial(material.id))!;
        downloadTransport.bytes = await sourceFiles
            .resolveMediaFile(scope, asset.relativePath)
            .readAsBytes();
      };
      expect(
        await CloudSyncCoordinator(
          scope: scope,
          identityProvider: session,
          consentProvider: consent,
          outbox: SqliteSyncOutbox(scope: scope, db: sourceDb),
          materials: source,
          mediaFiles: sourceFiles,
          transport: upload,
        ).runOne(),
        SyncRunResult.uploaded,
      );

      final sourceProgress = SqliteProgressRepository(
        scope: scope,
        db: sourceDb,
      );
      final ledger = FakeProgressLedger();
      final now = DateTime.now().toUtc();
      await sourceProgress.recordCheckpoint(
        stream: (
          ownerId: scope.ownerId,
          materialId: material.id,
          deviceId: 'mac',
          sessionId: 'played',
        ),
        positionMs: 2000,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(
        await ProgressSyncCoordinator(
          scope: scope,
          repository: sourceProgress,
          identityProvider: session,
          consentProvider: consent,
          transport: ledger,
          clock: () => now,
          random: () => 0.5,
        ).runOne(),
        ProgressSyncRunResult.committed,
      );

      final descriptor = upload.lastMaterialMetadata!;
      final cached = await download.download(descriptor);
      expect((await download.download(descriptor)).id, material.id);
      expect((await receiver.listMaterials()).single.id, material.id);
      expect(
        await receiverDb.customSelect('SELECT * FROM sync_outbox').get(),
        isEmpty,
      );

      final bundle = await MaterialPlaybackService(
        repository: receiver,
        storage: AppMediaStore(storage: receiverFiles, scope: scope),
        scope: scope,
      ).load(cached);
      expect(await File.fromUri(bundle.source.uri).readAsBytes(), bytes);

      final receiverProgress = SqliteProgressRepository(
        scope: scope,
        db: receiverDb,
      );
      final canonical = ledger.canonicals.values.single;
      await receiverProgress.mergeRemoteCanonical(
        checkpoint: canonical.checkpoint,
        revision: canonical.revision,
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(
        (await receiverProgress.canonical(
          bundle.material.id,
        ))?.checkpoint.positionMs,
        2000,
      );
    },
  );

  test('wrong owner path or absent consent prevents a download', () async {
    await expectLater(
      download.download(metadata('other')),
      throwsA(isA<SyncFailure>()),
    );
    consent.enabled = false;
    await expectLater(
      download.download(metadata(scope.ownerId)),
      throwsA(isA<SyncFailure>()),
    );
    expect(downloadTransport.requests, 0);
  });

  test('corruption and account change leave no published cache', () async {
    downloadTransport.bytes = [9, 9, 9, 9];
    await expectLater(
      download.download(metadata(scope.ownerId)),
      throwsA(
        isA<SyncFailure>().having(
          (error) => error.code,
          'code',
          'download_integrity_mismatch',
        ),
      ),
    );
    downloadTransport
      ..bytes = bytes
      ..afterBytes = () => session.identity = const SyncIdentity('other');
    await expectLater(
      download.download(metadata(scope.ownerId)),
      throwsA(
        isA<SyncFailure>().having(
          (error) => error.code,
          'code',
          'account_changed',
        ),
      ),
    );
    expect(await receiver.listMaterials(), isEmpty);
    expect(await receiverFiles.mediaDirectory(scope).list().toList(), isEmpty);
  });
}

final class _DownloadTransport implements CloudMaterialDownloadTransport {
  _DownloadTransport(this.bytes);

  List<int> bytes;
  void Function()? afterBytes;
  int requests = 0;

  @override
  Stream<List<int>> readAudio({
    required String uid,
    required String storagePath,
  }) async* {
    requests++;
    yield bytes;
    afterBytes?.call();
  }
}
