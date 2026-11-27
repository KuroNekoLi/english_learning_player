import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/core/files/app_media_store.dart';
import 'package:english_learning_player/core/sync/progress_policy.dart';
import 'package:english_learning_player/core/sync/sync_contracts.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/progress/data/sqlite_progress_repository.dart';
import 'package:english_learning_player/features/progress/domain/progress_models.dart';
import 'package:english_learning_player/features/progress/services/playback_progress_recorder.dart';
import 'package:english_learning_player/features/progress/services/progress_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_cloud_sync.dart';
import '../../fakes/fake_progress_ledger.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late AccountDatabaseService storage;
  late AccountScope scope;
  late SqliteMaterialRepository materials;
  late SqliteProgressRepository progress;
  late LocalDatabase database;
  late String materialId;
  late FakeSyncIdentityProvider identity;
  late FakeSyncConsentProvider consent;
  late FakeProgressLedger ledger;
  late DateTime now;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elp-wp09-');
    storage = AccountDatabaseService(supportDirectory: root);
    scope = AccountScope('progress-owner');
    database = await storage.open(scope);
    materials = SqliteMaterialRepository(scope: scope, database: database);
    progress = SqliteProgressRepository(scope: scope, db: database);
    materialId = await _importMaterial(storage, scope, materials);
    identity = FakeSyncIdentityProvider(SyncIdentity(scope.ownerId));
    consent = FakeSyncConsentProvider();
    ledger = FakeProgressLedger();
    now = DateTime.utc(2026, 11, 17, 8);
  });

  tearDown(() async {
    await materials.close();
    await root.delete(recursive: true);
  });

  ProgressStream stream({
    String device = 'mac',
    String session = 'session-1',
  }) => (
    ownerId: scope.ownerId,
    materialId: materialId,
    deviceId: device,
    sessionId: session,
  );

  ProgressSyncCoordinator coordinator() => ProgressSyncCoordinator(
    scope: scope,
    repository: progress,
    identityProvider: identity,
    consentProvider: consent,
    transport: ledger,
    clock: () => now,
    random: () => 0.5,
  );

  test(
    'checkpoint and immutable progress outbox are written together',
    () async {
      final checkpoint = await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 15000,
        state: CheckpointState.playing,
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(checkpoint.sequence, 1);
      expect(checkpoint.baseRevision, 0);
      expect(await progress.resumePosition(materialId), 15000);
      expect((await progress.mostRecentlyPlayed())?.materialId, materialId);
      final rows = await database
          .customSelect(
            "SELECT * FROM sync_outbox WHERE entity_type = 'progress'",
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('operation'), 'writeProgress');
      expect(rows.single.read<String>('state'), 'queued');
      expect(rows.single.read<String>('payload_hash'), isNotEmpty);
    },
  );

  test(
    'coordinator commits canonical progress and sequence advances',
    () async {
      await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 180000,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(await coordinator().runOne(), ProgressSyncRunResult.committed);
      final canonical = await progress.canonical(materialId);
      expect(canonical?.checkpoint.positionMs, 180000);
      expect(canonical?.revision, 1);
      final next = await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 1000,
        state: CheckpointState.playing,
        nowMs: now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      );
      expect(next.sequence, 2);
      expect(next.baseRevision, 1);
    },
  );

  test(
    'offline checkpoint becomes a candidate when canonical advanced',
    () async {
      await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 300000,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      final remotePhone = ProgressCheckpoint(
        stream: stream(device: 'iphone', session: 'phone-session'),
        positionMs: 720000,
        state: CheckpointState.paused,
        sequence: 1,
        baseRevision: 0,
      );
      await ledger.commit(
        uid: scope.ownerId,
        opId: 'phone-op',
        payloadHash: 'hash-phone',
        checkpoint: remotePhone,
      );
      expect(await coordinator().runOne(), ProgressSyncRunResult.committed);
      final canonical = await progress.canonical(materialId);
      expect(canonical?.checkpoint.positionMs, 720000);
      expect(canonical?.revision, 1);
      final candidates = await progress.unresolvedCandidates(materialId);
      expect(candidates, hasLength(1));
      expect(candidates.single.checkpoint.positionMs, 300000);
      expect(candidates.single.checkpoint.baseRevision, 0);
    },
  );

  test(
    'two offline device checkpoints merge as canonical plus conflict candidate',
    () async {
      final phoneDirectory = Directory('${root.path}/phone-profile')
        ..createSync(recursive: true);
      final phoneStorage = AccountDatabaseService(
        supportDirectory: phoneDirectory,
      );
      final phoneDatabase = await phoneStorage.open(scope);
      final phoneMaterials = SqliteMaterialRepository(
        scope: scope,
        database: phoneDatabase,
      );
      final phoneProgress = SqliteProgressRepository(
        scope: scope,
        db: phoneDatabase,
      );
      try {
        await phoneMaterials.insertAudio(
          asset: StoredAudioAsset(
            id: 'phone-asset',
            sha256: List.filled(64, 'b').join(),
            byteLength: 4,
            mediaType: 'audio/mp4',
            relativePath: 'media/${scope.storageKey}/phone.m4a',
          ),
          sourceKey: 'phone-material-source',
          title: 'Lesson',
          materialId: materialId,
          createdAt: now,
        );
        final phoneStream = stream(device: 'iphone', session: 'phone-offline');
        await progress.recordCheckpoint(
          stream: stream(device: 'mac', session: 'mac-offline'),
          positionMs: 30000,
          state: CheckpointState.paused,
          nowMs: now.millisecondsSinceEpoch,
        );
        await phoneProgress.recordCheckpoint(
          stream: phoneStream,
          positionMs: 90000,
          state: CheckpointState.paused,
          nowMs: now.millisecondsSinceEpoch,
        );

        expect(await coordinator().runOne(), ProgressSyncRunResult.committed);
        final phoneCoordinator = ProgressSyncCoordinator(
          scope: scope,
          repository: phoneProgress,
          identityProvider: identity,
          consentProvider: consent,
          transport: ledger,
          clock: () => now,
          random: () => 0.5,
        );
        expect(
          await phoneCoordinator.runOne(),
          ProgressSyncRunResult.committed,
        );
        expect(
          (await progress.canonical(materialId))?.checkpoint.positionMs,
          30000,
        );
        expect(
          (await phoneProgress.canonical(materialId))?.checkpoint.positionMs,
          30000,
        );
        final candidates = await phoneProgress.unresolvedCandidates(materialId);
        expect(candidates, hasLength(1));
        expect(candidates.single.checkpoint.positionMs, 90000);
        expect(candidates.single.checkpoint.baseRevision, 0);
      } finally {
        await phoneMaterials.close();
      }
    },
  );

  test(
    'remote update is stored without any playback or seek dependency',
    () async {
      await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 1000,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      await coordinator().runOne();
      final remote = ProgressCheckpoint(
        stream: stream(device: 'iphone', session: 'remote'),
        positionMs: 900000,
        state: CheckpointState.paused,
        sequence: 1,
        baseRevision: 1,
      );
      final result = await ledger.commit(
        uid: scope.ownerId,
        opId: 'remote-op',
        payloadHash: 'remote-hash',
        checkpoint: remote,
      );
      await progress.mergeRemoteCanonical(
        checkpoint: remote,
        revision: result.canonicalRevision,
        nowMs: now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      );
      expect(
        (await progress.canonical(materialId))?.checkpoint.positionMs,
        900000,
      );
    },
  );

  test(
    'receipt replays the original result and rejects opId payload changes',
    () async {
      final checkpoint = ProgressCheckpoint(
        stream: stream(),
        positionMs: 10,
        state: CheckpointState.paused,
        sequence: 1,
        baseRevision: 0,
      );
      final first = await ledger.commit(
        uid: scope.ownerId,
        opId: 'stable-op',
        payloadHash: 'same',
        checkpoint: checkpoint,
      );
      final replay = await ledger.commit(
        uid: scope.ownerId,
        opId: 'stable-op',
        payloadHash: 'same',
        checkpoint: checkpoint,
      );
      expect(replay, same(first));
      expect(ledger.writes, 1);
      await expectLater(
        ledger.commit(
          uid: scope.ownerId,
          opId: 'stable-op',
          payloadHash: 'different',
          checkpoint: checkpoint,
        ),
        throwsStateError,
      );
    },
  );

  test('candidate choice is queued with observed revision and only confirmed remotely', () async {
    await progress.recordCheckpoint(
      stream: stream(),
      positionMs: 300000,
      state: CheckpointState.paused,
      nowMs: now.millisecondsSinceEpoch,
    );
    final phone = ProgressCheckpoint(
      stream: stream(device: 'iphone', session: 'phone-session'),
      positionMs: 720000,
      state: CheckpointState.paused,
      sequence: 1,
      baseRevision: 0,
    );
    await ledger.commit(
      uid: scope.ownerId,
      opId: 'phone-op-for-resolution',
      payloadHash: 'phone-hash-for-resolution',
      checkpoint: phone,
    );
    await coordinator().runOne();
    final candidate = (await progress.unresolvedCandidates(materialId)).single;
    expect((await progress.canonical(materialId))?.revision, 1);

    await progress.resolveCandidate(
      candidateId: candidate.id,
      observedCanonicalRevision: 1,
      useCandidatePosition: true,
      resolutionStream: stream(device: 'mac', session: 'resolution-session'),
      nowMs: now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
    );
    final resolutionRow =
        (await database
                .customSelect(
                  "SELECT payload_json FROM sync_outbox WHERE entity_type = 'progress' AND operation = 'resolveProgress'",
                )
                .get())
            .single;
    final resolutionPayload = jsonDecode(
      resolutionRow.read<String>('payload_json'),
    ) as Map<String, dynamic>;
    expect(resolutionPayload['resolveCandidateId'], candidate.id);
    expect(resolutionPayload['observedCanonicalRevision'], 1);
    expect(resolutionPayload['positionMs'], 300000);
    expect(
      (await progress.canonical(materialId))?.checkpoint.positionMs,
      720000,
    );
    expect(await progress.unresolvedCandidates(materialId), hasLength(1));

    now = now.add(const Duration(seconds: 2));
    expect(await coordinator().runOne(), ProgressSyncRunResult.committed);
    expect(
      (await progress.canonical(materialId))?.checkpoint.positionMs,
      300000,
    );
    expect((await progress.canonical(materialId))?.revision, 2);
    expect(await progress.unresolvedCandidates(materialId), isEmpty);
  });

  test('authentication and consent gates leave checkpoint queued', () async {
    await progress.recordCheckpoint(
      stream: stream(),
      positionMs: 2,
      state: CheckpointState.paused,
      nowMs: now.millisecondsSinceEpoch,
    );
    identity.identity = null;
    expect(
      await coordinator().runOne(),
      ProgressSyncRunResult.waitingForAuthentication,
    );
    consent.enabled = false;
    identity.identity = SyncIdentity(scope.ownerId);
    expect(
      await coordinator().runOne(),
      ProgressSyncRunResult.waitingForConsent,
    );
    final row =
        (await database
                .customSelect(
                  "SELECT state FROM sync_outbox WHERE entity_type = 'progress'",
                )
                .get())
            .single;
    expect(row.read<String>('state'), 'queued');
    expect(ledger.writes, 0);
  });

  test(
    'account change during consent check leaves old owner operation queued',
    () async {
      await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 2000,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      consent.onCheck = (_) async {
        identity.identity = const SyncIdentity('account-b');
      };
      expect(
        await coordinator().runOne(),
        ProgressSyncRunResult.waitingForAuthentication,
      );
      final queued = await database
          .customSelect(
            "SELECT state FROM sync_outbox WHERE owner_id = ? AND entity_type = 'progress'",
            variables: [Variable.withString(scope.ownerId)],
          )
          .getSingle();
      expect(queued.read<String>('state'), 'queued');
      expect(ledger.writes, 0);

      consent.onCheck = null;
      identity.identity = SyncIdentity(scope.ownerId);
      expect(await coordinator().runOne(), ProgressSyncRunResult.committed);
    },
  );

  test(
    'account change after claiming an operation pauses before transport',
    () async {
      await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 2600,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      identity.identityResponses = [
        SyncIdentity(scope.ownerId), // Initial identity.
        SyncIdentity(scope.ownerId), // After consent.
        SyncIdentity(scope.ownerId), // After resuming the queue.
        const SyncIdentity('account-b'), // After the operation is claimed.
      ];
      expect(
        await coordinator().runOne(),
        ProgressSyncRunResult.waitingForAuthentication,
      );
      final paused = await database
          .customSelect(
            "SELECT state FROM sync_outbox WHERE entity_type = 'progress'",
          )
          .getSingle();
      expect(paused.read<String>('state'), 'waitingForAuth');
      expect(ledger.writes, 0);

      identity.identityResponses = null;
      identity.identity = SyncIdentity(scope.ownerId);
      expect(await coordinator().runOne(), ProgressSyncRunResult.committed);
    },
  );

  test('account change after a commit defers local ack and replays same receipt', () async {
    await progress.recordCheckpoint(
      stream: stream(),
      positionMs: 4500,
      state: CheckpointState.paused,
      nowMs: now.millisecondsSinceEpoch,
    );
    final transport = _SwitchAccountAfterCommit(ledger, identity);
    final guarded = ProgressSyncCoordinator(
      scope: scope,
      repository: progress,
      identityProvider: identity,
      consentProvider: consent,
      transport: transport,
      clock: () => now,
      random: () => 0.5,
    );
    expect(
      await guarded.runOne(),
      ProgressSyncRunResult.waitingForAuthentication,
    );
    expect(await progress.canonical(materialId), isNull);
    final waiting = await database
        .customSelect(
          "SELECT op_id, state FROM sync_outbox WHERE entity_type = 'progress'",
        )
        .getSingle();
    final opId = waiting.read<String>('op_id');
    expect(waiting.read<String>('state'), 'waitingForAuth');
    expect(ledger.writes, 1);

    identity.identity = SyncIdentity(scope.ownerId);
    expect(await coordinator().runOne(), ProgressSyncRunResult.committed);
    expect(ledger.writes, 1);
    expect((await progress.canonical(materialId))?.checkpoint.positionMs, 4500);
    final completed = await database
        .customSelect(
          "SELECT op_id, state FROM sync_outbox WHERE entity_type = 'progress'",
        )
        .getSingle();
    expect(completed.read<String>('op_id'), opId);
    expect(completed.read<String>('state'), 'completed');
  });

  test('a receipt naming another owner or material is never merged', () async {
    for (final remoteStream in [
      (
        ownerId: 'other',
        materialId: materialId,
        deviceId: 'server',
        sessionId: 'remote',
      ),
      (
        ownerId: scope.ownerId,
        materialId: 'other-material',
        deviceId: 'server',
        sessionId: 'remote',
      ),
    ]) {
      await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 3000,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      final transport = _FixedReceiptTransport(
        ProgressCommitResult(
          status: ProgressCommitStatus.conflict,
          candidateId: 'candidate',
          canonicalRevision: 1,
          canonicalCheckpoint: ProgressCheckpoint(
            stream: remoteStream,
            positionMs: 4000,
            state: CheckpointState.paused,
            sequence: 1,
            baseRevision: 0,
          ),
        ),
      );
      final runner = ProgressSyncCoordinator(
        scope: scope,
        repository: progress,
        identityProvider: identity,
        consentProvider: consent,
        transport: transport,
        clock: () => now,
        random: () => 0.5,
      );
      expect(await runner.runOne(), ProgressSyncRunResult.needsAttention);
    }
    expect(await progress.canonical(materialId), isNull);
    expect(await progress.unresolvedCandidates(materialId), isEmpty);
    final operations = await database
        .customSelect(
          "SELECT last_error FROM sync_outbox WHERE entity_type = 'progress' AND state = 'needsAttention'",
        )
        .get();
    expect(operations.map((row) => row.read<String>('last_error')), [
      'invalid_progress_receipt',
      'invalid_progress_receipt',
    ]);
  });

  test(
    'permission denial needs attention without retrying or changing canonical',
    () async {
      await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 12000,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      final failingTransport = _FailingProgressTransport(ledger)
        ..failure = const SyncFailure(
          SyncFailureKind.permissionDenied,
          'permission_denied',
        );
      final deniedCoordinator = ProgressSyncCoordinator(
        scope: scope,
        repository: progress,
        identityProvider: identity,
        consentProvider: consent,
        transport: failingTransport,
        clock: () => now,
        random: () => 0.5,
      );
      expect(
        await deniedCoordinator.runOne(),
        ProgressSyncRunResult.needsAttention,
      );
      final denied = await database
          .customSelect(
            "SELECT attempts, last_error, state FROM sync_outbox WHERE entity_type = 'progress'",
          )
          .getSingle();
      expect(denied.read<int>('attempts'), 0);
      expect(denied.read<String>('last_error'), 'permission_denied');
      expect(denied.read<String>('state'), 'needsAttention');
      expect(await progress.canonical(materialId), isNull);
      expect(ledger.writes, 0);
    },
  );

  test('transient failure retries with same operation and needs attention at limit', () async {
    await progress.recordCheckpoint(
      stream: stream(),
      positionMs: 2,
      state: CheckpointState.paused,
      nowMs: now.millisecondsSinceEpoch,
    );
    final failingTransport = _FailingProgressTransport(ledger);
    final retrying = ProgressSyncCoordinator(
      scope: scope,
      repository: progress,
      identityProvider: identity,
      consentProvider: consent,
      transport: failingTransport,
      clock: () => now,
      random: () => 0.5,
    );
    for (var attempt = 1; attempt <= 8; attempt++) {
      failingTransport.failure = const SyncFailure(
        SyncFailureKind.transient,
        'offline',
      );
      expect(
        await retrying.runOne(),
        attempt == 8
            ? ProgressSyncRunResult.needsAttention
            : ProgressSyncRunResult.retryScheduled,
      );
      now = now.add(const Duration(minutes: 2));
    }
    final row =
        (await database
                .customSelect(
                  "SELECT attempts, state FROM sync_outbox WHERE entity_type = 'progress'",
                )
                .get())
            .single;
    expect(row.read<int>('attempts'), 8);
    expect(row.read<String>('state'), 'needsAttention');
    final opId =
        (await database
                .customSelect(
                  "SELECT op_id FROM sync_outbox WHERE entity_type = 'progress'",
                )
                .get())
            .single
            .read<String>('op_id');
    failingTransport.failure = null;
    await progress.retryNeedsAttention(opId, now);
    expect(await retrying.runOne(), ProgressSyncRunResult.committed);
    final completed =
        (await database
                .customSelect(
                  "SELECT op_id, state FROM sync_outbox WHERE entity_type = 'progress'",
                )
                .get())
            .single;
    expect(completed.read<String>('op_id'), opId);
    expect(completed.read<String>('state'), 'completed');
  });

  test(
    'checkpoint data survives database reopen and account scope is isolated',
    () async {
      final deviceId = await progress.deviceId();
      await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 12345,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      await materials.close();
      database = await storage.open(scope);
      materials = SqliteMaterialRepository(scope: scope, database: database);
      progress = SqliteProgressRepository(scope: scope, db: database);
      expect(await progress.deviceId(), deviceId);
      expect(await progress.resumePosition(materialId), 12345);
      expect((await progress.mostRecentlyPlayed())?.materialId, materialId);
      expect((await progress.claimNext(now))?.checkpoint.positionMs, 12345);
      final other = AccountScope('other-progress-owner');
      final otherDb = await storage.open(other);
      final otherMaterials = SqliteMaterialRepository(
        scope: other,
        database: otherDb,
      );
      final otherProgress = SqliteProgressRepository(scope: other, db: otherDb);
      await _importMaterial(storage, other, otherMaterials);
      expect(await otherProgress.deviceId(), isNot(deviceId));
      expect(await otherProgress.canonical(materialId), isNull);
      expect(await otherProgress.resumePosition(materialId), isNull);
      expect(await otherProgress.mostRecentlyPlayed(), isNull);
      expect(await otherProgress.claimNext(now), isNull);
      await otherMaterials.close();
    },
  );

  test(
    'a remote revision does not replace a pending local resume position',
    () async {
      final local = await progress.recordCheckpoint(
        stream: stream(device: 'mac', session: 'local-session'),
        positionMs: 4000,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      final remote = ProgressCheckpoint(
        stream: stream(device: 'phone', session: 'remote-session'),
        positionMs: 3000,
        state: CheckpointState.paused,
        sequence: 1,
        baseRevision: 0,
      );

      await progress.mergeRemoteCanonical(
        checkpoint: remote,
        revision: 1,
        nowMs: now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      );

      expect(local.positionMs, 4000);
      expect(
        (await progress.canonical(materialId))?.checkpoint.positionMs,
        3000,
      );
      expect(await progress.resumePosition(materialId), 4000);
    },
  );

  test(
    'a remote canonical position appears in the local recent list',
    () async {
      final remote = ProgressCheckpoint(
        stream: stream(device: 'other-device', session: 'remote-session'),
        positionMs: 3600,
        state: CheckpointState.paused,
        sequence: 1,
        baseRevision: 0,
      );
      await progress.mergeRemoteCanonical(
        checkpoint: remote,
        revision: 1,
        nowMs: now.millisecondsSinceEpoch,
      );

      expect(await progress.resumePosition(materialId), 3600);
      expect((await progress.mostRecentlyPlayed())?.positionMs, 3600);
    },
  );

  test(
    'schema v4 upgrade creates progress tables without losing materials',
    () async {
      final db = database;
      await db.customStatement('DROP TABLE progress_conflicts');
      await db.customStatement('DROP TABLE progress_stream_state');
      await db.customStatement('DROP TABLE playback_progress');
      await db.customStatement('DROP INDEX IF EXISTS progress_conflicts_open');
      await db.customStatement('DROP INDEX IF EXISTS progress_outbox_due');
      await db.customStatement('PRAGMA user_version = 4');
      await materials.close();
      final upgraded = await storage.open(scope);
      materials = SqliteMaterialRepository(scope: scope, database: upgraded);
      database = upgraded;
      progress = SqliteProgressRepository(scope: scope, db: upgraded);
      expect((await materials.listMaterials()).single.id, materialId);
      await progress.recordCheckpoint(
        stream: stream(),
        positionMs: 20,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(await progress.claimNext(now), isNotNull);
    },
  );

  test('schema v12 upgrade backfills canonical resume positions', () async {
    final canonical = ProgressCheckpoint(
      stream: stream(device: 'old-device', session: 'old-session'),
      positionMs: 98765,
      state: CheckpointState.paused,
      sequence: 3,
      baseRevision: 2,
    );
    await progress.mergeRemoteCanonical(
      checkpoint: canonical,
      revision: 3,
      nowMs: now.millisecondsSinceEpoch,
    );
    await database.customStatement('DROP TABLE playback_resume_state');
    await database.customStatement('PRAGMA user_version = 12');
    await materials.close();

    database = await storage.open(scope);
    materials = SqliteMaterialRepository(scope: scope, database: database);
    progress = SqliteProgressRepository(scope: scope, db: database);

    expect(await progress.resumePosition(materialId), 98765);
    expect((await progress.mostRecentlyPlayed())?.positionMs, 98765);
  });

  test(
    'recorder checkpoints every 15 seconds and on seek, pause and exit',
    () async {
      var clock = now;
      final recorder = PlaybackProgressRecorder(
        repository: progress,
        stream: stream(),
        clock: () => clock,
      );
      await recorder.onPlaybackSnapshot(positionMs: 1000, playing: true);
      clock = clock.add(const Duration(seconds: 5));
      await recorder.onPlaybackSnapshot(positionMs: 6000, playing: true);
      clock = clock.add(const Duration(seconds: 10));
      await recorder.onPlaybackSnapshot(positionMs: 16000, playing: true);
      await recorder.onSeekCompleted(40000, playing: true);
      await recorder.onPauseCompleted();
      await recorder.onLifecycleExit();
      final rows = await database
          .customSelect(
            "SELECT payload_json FROM sync_outbox WHERE entity_type = 'progress' ORDER BY created_at_ms, op_id",
          )
          .get();
      expect(rows, hasLength(5));
      expect(
        rows.map((row) => row.read<String>('payload_json')),
        anyElement(
          allOf(contains('"positionMs":40000'), contains('"state":"paused"')),
        ),
      );
    },
  );
}

Future<String> _importMaterial(
  AccountDatabaseService storage,
  AccountScope scope,
  SqliteMaterialRepository materials,
) async {
  final importer = AudioImportService(
    repository: materials,
    mediaStore: AppMediaStore(storage: storage, scope: scope),
  );
  final result = await importer.importAudio(
    AudioImportSource(
      sourceKey: 'progress-fixture',
      name: 'progress.mp3',
      openRead: () async* {
        yield [1, 2, 3, 4];
      },
    ),
  );
  return result.material.id;
}

final class _FailingProgressTransport implements ProgressSyncTransport {
  _FailingProgressTransport(this.delegate);

  final ProgressSyncTransport delegate;
  SyncFailure? failure;

  @override
  Future<ProgressCommitResult> commit({
    required String uid,
    required String opId,
    required String payloadHash,
    required ProgressCheckpoint checkpoint,
    ProgressResolution? resolution,
  }) {
    final error = failure;
    if (error != null) throw error;
    return delegate.commit(
      uid: uid,
      opId: opId,
      payloadHash: payloadHash,
      checkpoint: checkpoint,
      resolution: resolution,
    );
  }
}

final class _SwitchAccountAfterCommit implements ProgressSyncTransport {
  _SwitchAccountAfterCommit(this.delegate, this.identity);

  final ProgressSyncTransport delegate;
  final FakeSyncIdentityProvider identity;
  bool _switched = false;

  @override
  Future<ProgressCommitResult> commit({
    required String uid,
    required String opId,
    required String payloadHash,
    required ProgressCheckpoint checkpoint,
    ProgressResolution? resolution,
  }) async {
    final result = await delegate.commit(
      uid: uid,
      opId: opId,
      payloadHash: payloadHash,
      checkpoint: checkpoint,
      resolution: resolution,
    );
    if (!_switched) {
      identity.identity = const SyncIdentity('account-b');
      _switched = true;
    }
    return result;
  }
}

final class _FixedReceiptTransport implements ProgressSyncTransport {
  const _FixedReceiptTransport(this.receipt);

  final ProgressCommitResult receipt;

  @override
  Future<ProgressCommitResult> commit({
    required String uid,
    required String opId,
    required String payloadHash,
    required ProgressCheckpoint checkpoint,
    ProgressResolution? resolution,
  }) async => receipt;
}
