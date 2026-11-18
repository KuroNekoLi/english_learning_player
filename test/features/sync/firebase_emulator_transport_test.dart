import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/files/app_media_store.dart';
import 'package:english_learning_player/core/sync/sqlite_sync_outbox.dart';
import 'package:english_learning_player/core/sync/progress_policy.dart';
import 'package:english_learning_player/core/sync/sync_contracts.dart';
import 'package:english_learning_player/features/auth/social_sign_in.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/progress/data/sqlite_progress_repository.dart';
import 'package:english_learning_player/features/progress/services/progress_sync_coordinator.dart';
import 'package:english_learning_player/features/sync/data/firebase_progress_transport.dart';
import 'package:english_learning_player/features/sync/data/firebase_subtitle_sync.dart';
import 'package:english_learning_player/features/subtitles/services/subtitle_import_service.dart';
import 'package:english_learning_player/features/sync/data/firebase_account_session.dart';
import 'package:english_learning_player/features/sync/data/firebase_endpoint.dart';
import 'package:english_learning_player/features/sync/data/firebase_material_transport.dart';
import 'package:english_learning_player/features/sync/services/cloud_material_download_service.dart';
import 'package:english_learning_player/features/sync/services/cloud_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_cloud_sync.dart';

void main() {
  test(
    'Firebase emulator: Google and Apple exchange mock credentials for isolated UIDs',
    () async {
      final http = FirebaseHttp();
      addTearDown(http.close);
      final endpoint = FirebaseEndpoint(
        project: 'demo-english-learning-player',
        bucket: 'demo-english-learning-player.appspot.com',
        apiKey: 'fake-api-key',
        emulatorHost: '127.0.0.1',
      );
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final uids = <String, String>{};
      for (final provider in SocialProvider.values) {
        final session = FirebaseAccountSession(endpoint, http);
        final mockCredential = ProviderIdToken(
          jsonEncode({
            'sub': '${provider.name}-$stamp',
            'email': '${provider.name}-$stamp@example.test',
            'email_verified': true,
          }),
          rawNonce: provider == SocialProvider.apple
              ? 'emulator-only-nonce'
              : null,
        );
        Future<SocialSignInResult?> authorize() async => mockCredential;
        final uid = await session.signInWithProvider(provider, authorize);
        expect(uid, isNotNull);
        expect(await session.tokenFor(uid!), isNotEmpty);
        uids[provider.name] = uid;
        session.signOut();
        await expectLater(session.tokenFor(uid), throwsA(isA<SyncFailure>()));
        expect(await session.signInWithProvider(provider, authorize), uid);
      }
      expect(uids.values.toSet(), hasLength(2));
    },
    skip: Platform.environment['ELP_RUN_FIREBASE_TEST'] != '1',
  );

  test(
    'Firebase emulator: two authenticated clients upload, download, and isolate accounts',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final root = await Directory.systemTemp.createTemp('elp-firebase-');
      addTearDown(() => root.delete(recursive: true));
      final http = FirebaseHttp();
      addTearDown(http.close);
      final endpoint = FirebaseEndpoint(
        project: 'demo-english-learning-player',
        bucket: 'demo-english-learning-player.appspot.com',
        apiKey: 'fake-api-key',
        emulatorHost: '127.0.0.1',
        progressRegion: 'us-central1',
      );
      final stamp = DateTime.now().microsecondsSinceEpoch;
      const password = 'emulator-fixture-only';

      Future<String> register(String email) async {
        final response = await http.send(
          'POST',
          endpoint.auth('signUp'),
          contentType: ContentType.json,
          bytes: FirebaseHttp.encode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }),
        );
        await http.requireSuccess(response);
        return (await http.json(response))['localId'] as String;
      }

      final ownerEmail =
          Platform.environment['ELP_SMOKE_EMAIL'] ??
          'stage3-$stamp@example.test';
      final uid = await register(ownerEmail);
      final sender = FirebaseAccountSession(endpoint, http);
      final receiver = FirebaseAccountSession(endpoint, http);
      expect(await sender.signIn(ownerEmail, password), uid);
      expect(await receiver.signIn(ownerEmail, password), uid);
      final scope = AccountScope(uid);
      final consent = FakeSyncConsentProvider();
      final senderFiles = AccountDatabaseService(
        supportDirectory: Directory('${root.path}/sender'),
      );
      final receiverFiles = AccountDatabaseService(
        supportDirectory: Directory('${root.path}/receiver'),
      );
      final senderDb = await senderFiles.open(scope);
      final receiverDb = await receiverFiles.open(scope);
      addTearDown(senderDb.close);
      addTearDown(receiverDb.close);
      final senderRepository = SqliteMaterialRepository(
        scope: scope,
        database: senderDb,
      );
      final receiverRepository = SqliteMaterialRepository(
        scope: scope,
        database: receiverDb,
      );
      final importer = AudioImportService(
        repository: senderRepository,
        mediaStore: AppMediaStore(storage: senderFiles, scope: scope),
      );
      final smokeMedia = Platform.environment['ELP_SMOKE_M4A'];
      final bytes = smokeMedia == null
          ? [1, 5, 9, 23]
          : await File(smokeMedia).readAsBytes();
      final first = await importer.importAudio(
        AudioImportSource(
          sourceKey: 'one',
          name: 'firebase-lesson.m4a',
          openRead: () => Stream.value(bytes),
        ),
      );
      final second = await importer.importAudio(
        AudioImportSource(
          sourceKey: 'two',
          name: 'firebase-duplicate.m4a',
          openRead: () => Stream.value(bytes),
        ),
      );
      final sending = FirebaseMaterialTransport(endpoint, sender, http);
      final coordinator = CloudSyncCoordinator(
        scope: scope,
        identityProvider: sender,
        consentProvider: consent,
        outbox: SqliteSyncOutbox(scope: scope, db: senderDb),
        materials: senderRepository,
        mediaFiles: senderFiles,
        transport: sending,
      );
      expect(
        await coordinator.runOne(),
        SyncRunResult.uploaded,
        reason: 'Storage write, read-back and Firestore publish',
      );
      expect(
        await coordinator.runOne(),
        SyncRunResult.uploaded,
        reason: 'Second material reuses an immutable remote asset',
      );
      final receiving = FirebaseMaterialTransport(endpoint, receiver, http);
      final catalog = await receiving.listMaterials(uid);
      expect(
        catalog.map((entry) => entry.materialId),
        unorderedEquals([first.material.id, second.material.id]),
      );
      final downloaded = await CloudMaterialDownloadService(
        scope: scope,
        identityProvider: receiver,
        consentProvider: consent,
        transport: receiving,
        repository: receiverRepository,
        mediaStore: AppMediaStore(storage: receiverFiles, scope: scope),
      ).download(catalog.first);
      final asset = (await receiverRepository.audioAssetForMaterial(
        downloaded.id,
      ))!;
      expect(
        await receiverFiles
            .resolveMediaFile(scope, asset.relativePath)
            .readAsBytes(),
        bytes,
      );
      expect(
        await receiverDb.customSelect('SELECT * FROM sync_outbox').get(),
        isEmpty,
      );

      final subtitleImport = SubtitleImportService(
        repository: senderRepository,
      );
      for (final language in ['en', 'zh-TW']) {
        await subtitleImport.importBytes(
          ownerId: uid,
          materialId: downloaded.id,
          languageTag: language,
          sourceName: 'synthetic-$language.srt',
          bytes: utf8.encode(
            '1\n00:00:00,300 --> 00:00:03,500\nCloud $language\n',
          ),
          manual: false,
          offsetMs: 100,
        );
      }
      final publishingSubtitles = FirebaseSubtitleSync(
        uid: uid,
        transport: sending,
        repository: senderRepository,
        consent: consent,
      );
      await publishingSubtitles.publish(downloaded.id);
      await publishingSubtitles.publish(downloaded.id);
      final receivingSubtitles = FirebaseSubtitleSync(
        uid: uid,
        transport: receiving,
        repository: receiverRepository,
        consent: consent,
      );
      await receivingSubtitles.download(downloaded.id);
      await receivingSubtitles.download(downloaded.id);
      final subtitleTracks = await receiverRepository.listSubtitleTracks(
        downloaded.id,
      );
      expect(subtitleTracks, hasLength(2));
      expect(
        subtitleTracks.map((track) => track.languageTag),
        unorderedEquals(['en', 'zh-tw']),
      );
      expect(
        subtitleTracks.every(
          (track) => track.isSelected && track.offsetMs == 100,
        ),
        isTrue,
      );

      final macProgress = SqliteProgressRepository(scope: scope, db: senderDb);
      final phoneProgress = SqliteProgressRepository(
        scope: scope,
        db: receiverDb,
      );
      final macTransport = FirebaseProgressTransport(
        endpoint,
        sender,
        http,
        sending,
      );
      final phoneTransport = FirebaseProgressTransport(
        endpoint,
        receiver,
        http,
        receiving,
      );
      final now = DateTime.now().toUtc();
      ProgressStream stream(String device) => (
        ownerId: uid,
        materialId: downloaded.id,
        deviceId: device,
        sessionId: 'session',
      );
      await macProgress.recordCheckpoint(
        stream: stream('mac'),
        positionMs: 1800,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      await phoneProgress.recordCheckpoint(
        stream: stream('phone'),
        positionMs: 2400,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      Future<ProgressSyncRunResult> syncProgress(
        SqliteProgressRepository progress,
        FirebaseAccountSession account,
        FirebaseProgressTransport transport,
      ) => ProgressSyncCoordinator(
        scope: scope,
        repository: progress,
        identityProvider: account,
        consentProvider: consent,
        transport: transport,
        clock: () => now,
        random: () => 0.5,
      ).runOne();

      expect(
        await syncProgress(macProgress, sender, macTransport),
        ProgressSyncRunResult.committed,
      );
      expect(
        await syncProgress(phoneProgress, receiver, phoneTransport),
        ProgressSyncRunResult.committed,
      );
      final candidates = await phoneProgress.unresolvedCandidates(
        downloaded.id,
      );
      expect(candidates.single.checkpoint.positionMs, 2400);
      final confirmed = (await phoneTransport.canonical(uid, downloaded.id))!;
      expect(confirmed.checkpoint.positionMs, 1800);
      expect(confirmed.revision, 1);
      await phoneProgress.resolveCandidate(
        candidateId: candidates.single.id,
        observedCanonicalRevision: 1,
        useCandidatePosition: true,
        resolutionStream: stream('phone'),
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(
        await syncProgress(phoneProgress, receiver, phoneTransport),
        ProgressSyncRunResult.committed,
      );
      expect(
        (await macTransport.canonical(
          uid,
          downloaded.id,
        ))?.checkpoint.positionMs,
        2400,
      );
      expect(await phoneProgress.unresolvedCandidates(downloaded.id), isEmpty);

      final otherEmail = 'other-$stamp@example.test';
      final otherUid = await register(otherEmail);
      await receiver.signIn(otherEmail, password);
      expect(await receiving.listMaterials(otherUid), isEmpty);
      await expectLater(
        receiving.listMaterials(uid),
        throwsA(isA<SyncFailure>()),
      );
    },
    skip: Platform.environment['ELP_RUN_FIREBASE_TEST'] != '1'
        ? 'Run with Auth, Firestore and Storage Firebase Emulators.'
        : false,
  );
}
