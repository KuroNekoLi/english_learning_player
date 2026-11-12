import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/sync/sqlite_sync_outbox.dart';
import 'package:english_learning_player/core/sync/sync_contracts.dart';
import 'package:english_learning_player/core/files/app_media_store.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/sync/services/cloud_sync_coordinator.dart';
import '../../fakes/fake_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late AccountDatabaseService files;
  late AccountScope scope;
  late SqliteMaterialRepository materials;
  late LocalDatabase database;
  late SqliteSyncOutbox outbox;
  late FakeSyncIdentityProvider identity;
  late FakeSyncConsentProvider consent;
  late FakeCloudSyncTransport transport;
  late DateTime now;
  late CloudSyncCoordinator coordinator;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elp-wp08-');
    files = AccountDatabaseService(supportDirectory: root);
    scope = AccountScope('alice');
    database = await files.open(scope);
    materials = SqliteMaterialRepository(scope: scope, database: database);
    outbox = SqliteSyncOutbox(scope: scope, db: database);
    identity = FakeSyncIdentityProvider(const SyncIdentity('alice'));
    consent = FakeSyncConsentProvider();
    transport = FakeCloudSyncTransport();
    now = DateTime.now().toUtc();
    coordinator = CloudSyncCoordinator(
      scope: scope,
      identityProvider: identity,
      consentProvider: consent,
      outbox: outbox,
      materials: materials,
      mediaFiles: files,
      transport: transport,
      clock: () => now,
      random: () => 0.5,
    );
    await _importOne(materials, files, scope);
    now = DateTime.now().toUtc().add(const Duration(seconds: 1));
  });

  tearDown(() async {
    await materials.close();
    await root.delete(recursive: true);
  });

  test(
    'uploads verified local bytes then publishes metadata and CloudReady',
    () async {
      final rows = await database
          .customSelect('SELECT * FROM sync_outbox')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('state'), 'queued');
      expect(
        rows.single.read<int>('next_retry_at_ms'),
        lessThanOrEqualTo(now.millisecondsSinceEpoch),
      );
      expect(await coordinator.runOne(), SyncRunResult.uploaded);
      expect(transport.uploadCount, 1);
      expect(transport.assetMetadataCount, 1);
      expect(transport.materialMetadataCount, 1);
      final materialData = transport.lastMaterialMetadata!.toFirestoreDocument(
        'alice',
      );
      expect(materialData['ownerId'], 'alice');
      expect(materialData['status'], 'cloudReady');
      expect(materialData.containsKey('localPath'), isFalse);
      expect(transport.lastAssetMetadata!.toStorageCustomMetadata('alice'), {
        'ownerId': 'alice',
        'assetId': transport.lastAssetMetadata!.assetId,
        'sha256': transport.lastAssetMetadata!.sha256,
        'opId': transport.lastAssetMetadata!.opId,
        'payloadHash': transport.lastAssetMetadata!.payloadHash,
      });
      expect(
        (await materials.listMaterials()).single.status,
        MaterialStatus.cloudReady,
      );
      expect(await coordinator.runOne(), SyncRunResult.idle);
      expect(transport.uploadCount, 1);
    },
  );

  test(
    'metadata failure retries with same opId without claiming CloudReady early',
    () async {
      transport.materialMetadataFailure = const SyncFailure(
        SyncFailureKind.transient,
        'emulator_unavailable',
      );
      expect(await coordinator.runOne(), SyncRunResult.retryScheduled);
      final firstOp = transport.lastOpId;
      expect(
        (await materials.listMaterials()).single.status,
        MaterialStatus.localReady,
      );
      var operation = await _onlyOutboxRow(database);
      expect(operation.read<String>('state'), 'queued');
      expect(operation.read<int>('attempts'), 1);
      expect(operation.read<String>('last_error'), 'emulator_unavailable');

      transport.materialMetadataFailure = null;
      now = now.add(const Duration(minutes: 1));
      expect(await coordinator.runOne(), SyncRunResult.uploaded);
      expect(transport.lastOpId, firstOp);
      expect(transport.uploadCount, 2);
      expect(
        (await materials.listMaterials()).single.status,
        MaterialStatus.cloudReady,
      );
      operation = await _onlyOutboxRow(database);
      expect(operation.read<String>('state'), 'completed');
    },
  );

  test(
    'pauses without auth and resumes the same durable operation for the same UID',
    () async {
      identity.identity = null;
      expect(
        await coordinator.runOne(),
        SyncRunResult.waitingForAuthentication,
      );
      expect(
        (await materials.listMaterials()).single.status,
        MaterialStatus.localReady,
      );
      expect((await _onlyOutboxRow(database)).read<String>('state'), 'queued');

      identity.identity = const SyncIdentity('alice');
      expect(await coordinator.runOne(), SyncRunResult.uploaded);
      expect(transport.uploadCount, 1);
    },
  );

  test(
    'requires explicit cloud-sync consent before dispatching imported media',
    () async {
      consent.enabled = false;
      expect(await coordinator.runOne(), SyncRunResult.waitingForConsent);
      expect(transport.uploadCount, 0);
      expect(
        (await materials.listMaterials()).single.status,
        MaterialStatus.localReady,
      );
      consent.enabled = true;
      expect(await coordinator.runOne(), SyncRunResult.uploaded);
    },
  );

  test(
    'account change during blob transfer pauses before publishing metadata',
    () async {
      transport.afterUpload = () async {
        identity.identity = const SyncIdentity('bob');
      };
      expect(
        await coordinator.runOne(),
        SyncRunResult.waitingForAuthentication,
      );
      expect(transport.materialMetadataCount, 0);
      expect(
        (await _onlyOutboxRow(database)).read<String>('state'),
        'waitingForAuth',
      );

      identity.identity = const SyncIdentity('alice');
      transport.afterUpload = null;
      expect(await coordinator.runOne(), SyncRunResult.uploaded);
    },
  );

  test(
    'permanent permission failure becomes visible error and does not retry',
    () async {
      transport.uploadFailure = const SyncFailure(
        SyncFailureKind.permissionDenied,
        'permission_denied',
      );
      expect(await coordinator.runOne(), SyncRunResult.needsAttention);
      expect(
        (await materials.listMaterials()).single.status,
        MaterialStatus.error,
      );
      final row = await _onlyOutboxRow(database);
      expect(row.read<String>('state'), 'needsAttention');
      expect(row.read<int>('attempts'), 0);
      expect(transport.materialMetadataCount, 0);
    },
  );

  test('invalid local media integrity stops before network writes', () async {
    final material = (await materials.listMaterials()).single;
    final asset = (await materials.audioAssetForMaterial(material.id))!;
    await files.resolveMediaFile(scope, asset.relativePath).writeAsBytes([
      9,
      9,
      9,
    ]);
    expect(await coordinator.runOne(), SyncRunResult.needsAttention);
    expect(transport.uploadCount, 0);
    expect(
      (await materials.listMaterials()).single.status,
      MaterialStatus.error,
    );
  });

  test('limits transient retry count and applies capped jitter', () async {
    transport.uploadFailure = const SyncFailure(
      SyncFailureKind.transient,
      'offline',
    );
    for (var attempt = 1; attempt <= 8; attempt++) {
      final result = await coordinator.runOne();
      final retryRow = await _onlyOutboxRow(database);
      expect(
        result,
        attempt == 8
            ? SyncRunResult.needsAttention
            : SyncRunResult.retryScheduled,
        reason:
            'retry attempt $attempt, persisted=${retryRow.read<int>('attempts')} state=${retryRow.read<String>('state')}',
      );
      expect(retryRow.read<int>('attempts'), attempt);
      now = now.add(const Duration(minutes: 2));
    }
    final row = await _onlyOutboxRow(database);
    expect(row.read<int>('attempts'), 8);
    expect(row.read<String>('state'), 'needsAttention');
    final opId = row.read<String>('op_id');
    expect(
      nextRetryAt(DateTime.utc(2026), 10, 0.5),
      DateTime.utc(2026).add(const Duration(seconds: 45)),
    );
    transport.uploadFailure = null;
    await outbox.retryNeedsAttention('alice', opId, now);
    expect(
      (await materials.listMaterials()).single.status,
      MaterialStatus.localReady,
    );
    expect(await coordinator.runOne(), SyncRunResult.uploaded);
    expect(transport.lastOpId, opId);
  });

  test(
    'duplicate local import does not create another cloud operation',
    () async {
      final importer = AudioImportService(
        repository: materials,
        mediaStore: AppMediaStore(storage: files, scope: scope),
      );
      final duplicate = await importer.importAudio(
        AudioImportSource(
          sourceKey: 'source-key',
          name: 'lesson.mp3',
          openRead: () async* {
            yield [1, 2, 3, 4];
          },
        ),
      );
      expect(duplicate.wasDuplicate, isTrue);
      expect(
        await database.customSelect('SELECT op_id FROM sync_outbox').get(),
        hasLength(1),
      );
    },
  );

  test('outbox cannot be queried through a different owner scope', () async {
    await expectLater(outbox.claimNext('bob', now), throwsArgumentError);
  });

  test('material insert and outbox enqueue roll back together', () async {
    await database.customStatement('''
      CREATE TRIGGER reject_test_outbox BEFORE INSERT ON sync_outbox
      BEGIN SELECT RAISE(ABORT, 'injected outbox failure'); END
    ''');
    final importer = AudioImportService(
      repository: materials,
      mediaStore: AppMediaStore(storage: files, scope: scope),
    );
    await expectLater(
      importer.importAudio(
        AudioImportSource(
          sourceKey: 'source-that-fails',
          name: 'different.mp3',
          openRead: () async* {
            yield [5, 6, 7, 8];
          },
        ),
      ),
      throwsA(isA<Exception>()),
    );
    final library = await materials.listMaterials();
    expect(library, hasLength(1));
    expect(library.single.title, 'lesson');
    expect(
      await database.customSelect('SELECT op_id FROM sync_outbox').get(),
      hasLength(1),
    );
  });

  test('queued cloud operation survives database reopen', () async {
    await materials.close();
    database = await files.open(scope);
    materials = SqliteMaterialRepository(scope: scope, database: database);
    outbox = SqliteSyncOutbox(scope: scope, db: database);
    coordinator = CloudSyncCoordinator(
      scope: scope,
      identityProvider: identity,
      consentProvider: consent,
      outbox: outbox,
      materials: materials,
      mediaFiles: files,
      transport: transport,
      clock: () => now,
      random: () => 0.5,
    );

    expect(await coordinator.runOne(), SyncRunResult.uploaded);
    expect(
      (await materials.listMaterials()).single.status,
      MaterialStatus.cloudReady,
    );
  });

  test('rejects a UID that differs from its local account scope', () async {
    identity.identity = const SyncIdentity('bob');
    await expectLater(coordinator.runOne(), throwsStateError);
    expect(transport.uploadCount, 0);
  });
}

Future<void> _importOne(
  SqliteMaterialRepository materials,
  AccountDatabaseService files,
  AccountScope scope,
) async {
  final importer = AudioImportService(
    repository: materials,
    mediaStore: AppMediaStore(storage: files, scope: scope),
  );
  await importer.importAudio(
    AudioImportSource(
      sourceKey: 'source-key',
      name: 'lesson.mp3',
      openRead: () async* {
        yield [1, 2];
        yield [3, 4];
      },
    ),
  );
}

Future<dynamic> _onlyOutboxRow(LocalDatabase database) async =>
    (await database.customSelect('SELECT * FROM sync_outbox').get()).single;
