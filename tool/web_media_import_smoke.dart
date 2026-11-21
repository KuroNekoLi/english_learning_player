import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:drift/drift.dart' show Variable;
import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/core/audio/audio_media_session_port.dart';
import 'package:english_learning_player/core/audio/just_audio_adapter.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/db/web_account_database_service.dart';
import 'package:english_learning_player/core/files/web_media_store.dart';
import 'package:english_learning_player/core/sync/progress_policy.dart';
import 'package:english_learning_player/features/bookmarks/data/sqlite_bookmark_repository.dart';
import 'package:english_learning_player/features/bookmarks/domain/bookmark.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/library/services/media_selection_import_service.dart';
import 'package:english_learning_player/features/player/services/material_playback_loader.dart';
import 'package:english_learning_player/features/player/services/player_playback_startup.dart';
import 'package:english_learning_player/features/progress/data/sqlite_progress_repository.dart';
import 'package:english_learning_player/features/subtitles/services/subtitle_import_service.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _syntheticMp3Base64 =
    'SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYzLjEuMTAyAAAAAAAAAAAAAAD/+0DAAAAAAAAAAAAAAAAAAAAAAABJbmZvAAAADwAAAAsAAAUzADc3Nzc3Nzc3N0tLS0tLS0tLS19fX19fX19fX3Nzc3Nzc3Nzc4eHh4eHh4eHh5ubm5ubm5ubm6+vr6+vr6+vr8PDw8PDw8PDw9fX19fX19fX1+vr6+vr6+vr6////////////wAAAABMYXZjNjMuMS4AAAAAAAAAAAAAAAAkBC8AAAAAAAAFMzjQzEEAAAAAAP/7EMQAAAR0E1VUkIAwpgmvNxogAgABrTlAAAFZOj1QUAgGCQHwfB8HygIAgGEQfB/UCDsTh/iDcAST9sBgOBwOAAAAAAAoiSqZFGQI6QJIFqP3hQHwExvwIpQvqBoS/CQNKgAAAZZE//sSxAKCRNgbM73QADCdg6Rln2RMwAAA+r6l/VsINGk8omcQ9mGQLgIFS/yAZBZ/rkdlD79vsAIA3/SEMMc3KDBlC1MyRhczEwtTBoAwONkxyzEGMV9B+WA5/f//9FUw0OMOHTHTgz6D//sQxAUDRQQfGA37IkCuA+LJr2hIMK8b41DOHDTrG0MJ4G01zAIGbqh1fmsGyaWhz9f0ZgoIY0aapceXuYgwzhuU51G34M8YhYRJ8KhsHRqWZqMxkCDL6QHD/1ZfR1oAAACgAxgAAF3/+xLEBIJFrB8jrPsCYJaDpPWPYEzQaAYCJo8GCQHCZPbvJk0BtmCCBYW1WMBimmBeqK5Oq/9HkP1A0MCgS9Yhac5UME0HkygkTzJzB5MEwBo6rAIyzgJmqekC1n2f7jCxAwwfMZPDOIn/+xDEBQJFAB8YDfsiQJcDZjSe8A4wnx0jSk60NIUcgwjAdTNUAwpwoHdybALNp0Ofp+gKVgSBgNsQLTmDQXGpMMHPhcAhuXYWEXOiA/h8+nU6j/VYxVgWqjChEw0eMWPTNYwwlB3TRv/7EsQHgkT8HxgN+yJAjAOm9G5sDv77NE4dMwhQeDIZBxRxGnjoAsl+zwb/T9hd0oEehDvqCGCQmbYp56YmGCCm7W3YXm7eBSmHnYLMT/9/JQACCLpWIAABKoi6SeoNERmzmHpQIqh0Wf/7EMQMAMSgHzmuaYQwkAPjga9oTScDUPXu2K6hi17P9OtoAODmYGHBbmFsG4alrmhqGBvGFyCKcRYZQ8Y06YqEBAj/1AwAAggcBwMAACkLNxS2BgWmO8NnyVoSm4wM/LXm2sv6R3+///sSxBECRIgdN6T3QHCBg6e0zbBW3fpU2oFs9w/A4BQE47BOLAUREw2tkgVhPQo0vt2/79N4/IoABAoUQAMAABYBWRIIQSHBkFOR/2xcFDkxV+mIs1tGe/p///ax0MFmaEHFWmF4GAaq//sQxBiAxIQdNaT3QHCPA+OBr2hNbLxqYBhGF6B6cRUZQ8Ys6YaIDAj/1C0wQLMDGDCDcxuAMF4bkzC97TL0GxME0HIYdJkgF6dbQRU0GeM/oSAMttstrjcbi6VC0DkbA37L3nds0zT/+xLEHgBEuB8aDfsiYPaOKfayYAbLJYGyhrkU3oHCydwCAAgWAAjLvYhyAAQ55MnbE78Y92xMmOBAMbVKAAAsEYrFgwEAAAAAAATVMlzLv+Asl3Y7/zT5OJ57Zd/htIWaMk8BhAEw1yv/+xDEFgAIaIFRuZgAEAAANIOAAAThdMc8TQVa0a/BuINlD+C+E5/+VC6XjGpMQU1FNC4wqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqg==';

void main() => runApp(const WebMediaImportSmokeApp());

final class WebMediaImportSmokeApp extends StatefulWidget {
  const WebMediaImportSmokeApp({super.key});

  @override
  State<WebMediaImportSmokeApp> createState() => _WebMediaImportSmokeAppState();
}

final class _WebMediaImportSmokeAppState extends State<WebMediaImportSmokeApp> {
  late final Future<_SmokeReady?> _prepared = _prepareSmoke();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WP-17 media smoke',
    home: Scaffold(
      appBar: AppBar(title: const Text('WP-17 Web media smoke')),
      body: Center(
        child: FutureBuilder<_SmokeReady?>(
          future: _prepared,
          builder: (context, snapshot) {
            final ready = snapshot.data;
            final status = snapshot.hasError
                ? 'FAIL: ${snapshot.error}'
                : ready?.status ?? 'PREPARING';
            _setStatus(status);
            if (ready != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (ready.stage == _SmokeStage.playback) {
                  _mountAction(
                    'Play sentence loop',
                    () => _playSentenceLoop(ready),
                  );
                } else {
                  _mountAction('Play offline media', () => _playOffline(ready));
                }
              });
            }
            return Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                status,
                key: const ValueKey('webMediaSmokeResult'),
              ),
            );
          },
        ),
      ),
    ),
  );

  Future<_SmokeReady?> _prepareSmoke() async {
    const runIdKey = 'wp17-web-media-smoke-run-id';
    const stageKey = 'wp17-web-media-smoke-stage';
    const backendKey = 'wp17-web-media-smoke-backend';
    var runId = web.window.localStorage.getItem(runIdKey);
    if (runId == null) {
      runId = DateTime.now().microsecondsSinceEpoch.toString();
      web.window.localStorage.setItem(runIdKey, runId);
    }
    final scope = AccountScope('web-smoke-$runId');
    final opened = await const WebAccountDatabaseService().open(scope);
    if (!opened.storageIsSafeForWrites) {
      throw StateError('Unsafe browser database mode.');
    }
    final repository = SqliteMaterialRepository(
      scope: scope,
      database: opened.database,
    );
    final mediaStore = WebMediaStore(scope);
    final stage = web.window.localStorage.getItem(stageKey);
    if (stage == null) {
      final syntheticMp3 = base64.decode(_syntheticMp3Base64);
      final emptySelection = await MediaSelectionImportService(
        ownerId: scope.ownerId,
        repository: repository,
        audioImporter: AudioImportService(
          repository: repository,
          mediaStore: mediaStore,
        ),
        subtitleImporter: SubtitleImportService(repository: repository),
      ).importFiles(const []);
      if (emptySelection.importedMaterials.isNotEmpty ||
          emptySelection.audioFailures != 0 ||
          emptySelection.subtitleFailures != 0) {
        throw StateError(
          'An empty or cancelled selection should have no effect.',
        );
      }
      final failure = await MediaSelectionImportService(
        ownerId: scope.ownerId,
        repository: repository,
        audioImporter: AudioImportService(
          repository: repository,
          mediaStore: WebMediaStore.forTesting(
            scope,
            beforeWrite: (_) async => throw StateError('QuotaExceededError'),
          ),
        ),
        subtitleImporter: SubtitleImportService(repository: repository),
      ).importFiles([_source('failed-lesson.mp3', syntheticMp3)]);
      final outbox = await opened.database
          .customSelect(
            'SELECT op_id FROM sync_outbox WHERE owner_id = ?',
            variables: [Variable.withString(scope.ownerId)],
          )
          .get();
      if (failure.audioFailures != 1 ||
          (await repository.listMaterials()).isNotEmpty ||
          outbox.isNotEmpty) {
        throw StateError(
          'A failed media write published a material or outbox row.',
        );
      }

      final result =
          await MediaSelectionImportService(
            ownerId: scope.ownerId,
            repository: repository,
            audioImporter: AudioImportService(
              repository: repository,
              mediaStore: mediaStore,
            ),
            subtitleImporter: SubtitleImportService(repository: repository),
          ).importFiles([
            _source('lesson.mp3', syntheticMp3),
            _source(
              'lesson.en.srt',
              utf8.encode('1\n00:00:00,000 --> 00:00:02,000\nHello Web\n'),
            ),
            _source(
              'lesson.zh-TW.srt',
              utf8.encode('1\n00:00:00,000 --> 00:00:02,000\n網頁測試\n'),
            ),
          ]);
      if (result.importedMaterials.length != 1 ||
          result.subtitlesImported != 2) {
        throw StateError('Unexpected import result: $result');
      }
      final duplicate = await AudioImportService(
        repository: repository,
        mediaStore: mediaStore,
      ).importAudio(_source('lesson.mp3', syntheticMp3));
      if (!duplicate.wasDuplicate ||
          (await repository.listMaterials()).length != 1) {
        throw StateError('Browser media SHA-256 deduplication failed.');
      }
      final material = result.importedMaterials.single;
      final englishTrack = (await repository.listSubtitleTracks(
        material.id,
      )).firstWhere((track) => track.languageTag == 'en');
      final cue = englishTrack.cues.single;
      final bookmarks = SqliteBookmarkRepository(
        scope: scope,
        database: opened.database,
      );
      await bookmarks.addBookmark(
        Bookmark(
          id: 'web-smoke-bookmark',
          ownerId: scope.ownerId,
          materialId: material.id,
          anchor: BookmarkCueAnchor(
            trackId: englishTrack.id,
            trackRevision: englishTrack.revision,
            languageTag: englishTrack.languageTag,
            cueId: cue.id,
            cueText: cue.text,
            startMs: cue.startMs,
            endMs: cue.endMs,
          ),
          createdAt: DateTime.now().toUtc(),
        ),
      );
      final progressRepository = SqliteProgressRepository(
        scope: scope,
        db: opened.database,
      );
      final progressDeviceId = await progressRepository.deviceId();
      final stream = (
        ownerId: scope.ownerId,
        materialId: material.id,
        deviceId: progressDeviceId,
        sessionId: 'web-smoke-session',
      );
      await progressRepository.mergeRemoteCanonical(
        checkpoint: ProgressCheckpoint(
          stream: stream,
          positionMs: 80,
          state: CheckpointState.paused,
          sequence: 1,
          baseRevision: 0,
        ),
        revision: 1,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      web.window.localStorage.setItem(
        backendKey,
        mediaStore.lastWriteBackend?.name ?? 'unknown',
      );
      await repository.close();
      web.window.localStorage.setItem(stageKey, 'imported');
      web.window.location.reload();
      return null;
    }
    final restoredMaterial = (await repository.listMaterials()).single;
    final bundle = await MaterialPlaybackService(
      repository: repository,
      storage: mediaStore,
      scope: scope,
    ).load(restoredMaterial);
    if (bundle.englishTrack == null ||
        bundle.chineseTrack == null ||
        bundle.source.uri.scheme != 'blob') {
      throw StateError(
        'Reopened media or bilingual subtitles were not restored.',
      );
    }
    if ((await SqliteBookmarkRepository(
          scope: scope,
          database: opened.database,
        ).listBookmarks()).length !=
        1) {
      throw StateError('The bookmark did not survive browser reload.');
    }
    final engine = JustAudioAdapter();
    final progressRepository = SqliteProgressRepository(
      scope: scope,
      db: opened.database,
    );
    await PlayerPlaybackStartup(engine).prepare(
      bundle,
      mediaSession: () async => const NoopAudioMediaSession(),
      progressRepository: () async => progressRepository,
      restorePosition: true,
      isCurrent: () => true,
    );
    if (engine.snapshot.positionMs != 80) {
      throw StateError('Confirmed progress was not restored after reload.');
    }
    final durationMs = engine.snapshot.durationMs;
    if (durationMs == null || durationMs <= 0) {
      throw StateError('The Web audio decoder did not report a duration.');
    }
    await engine.seekTo(Duration(milliseconds: durationMs ~/ 2));
    if (engine.snapshot.positionMs <= 0) {
      throw StateError('Web seek did not update the playback position.');
    }
    final mediaBackend =
        web.window.localStorage.getItem(backendKey) ?? 'unknown';
    final playbackStage = stage == 'played'
        ? _SmokeStage.offline
        : _SmokeStage.playback;
    if (playbackStage == _SmokeStage.offline &&
        web.window.navigator.serviceWorker.controller == null) {
      throw StateError(
        'The offline reload was not controlled by a service worker.',
      );
    }
    final status = playbackStage == _SmokeStage.playback
        ? 'READY_FOR_GESTURE | importFailure=PASS | OPFS=$mediaBackend | '
              'fallback=PASS | dedupe=PASS | bookmark=PASS | resume=PASS | '
              'browserReload=PASS | decode=PASS | seek=PASS'
        : 'OFFLINE_RESTORED | appShell=PASS | media=PASS | subtitles=PASS | '
              'bookmark=PASS | resume=PASS | serviceWorker=PASS | '
              'decode=PASS | seek=PASS';
    return _SmokeReady(
      status: status,
      stage: playbackStage,
      engine: engine,
      repository: repository,
      databaseName: opened.chosenImplementation.name,
      backendName: mediaBackend,
    );
  }

  Future<void> _playSentenceLoop(_SmokeReady ready) async {
    try {
      final positions = <int>[];
      final subscription = ready.engine.snapshots.listen((snapshot) {
        if (snapshot.playing) positions.add(snapshot.positionMs);
      });
      await ready.engine.play();
      await ready.engine.setSentenceLoop(TimeRange(0, 150));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final state = ready.engine.snapshot;
      final loop = state.currentLoop;
      await subscription.cancel();
      final observedRestart = positions.asMap().entries.any(
        (entry) =>
            entry.key > 0 &&
            positions[entry.key - 1] >= 130 &&
            entry.value < 40,
      );
      if (!state.playing ||
          loop?.startMs != 0 ||
          loop?.endMs != 150 ||
          !observedRestart) {
        throw StateError(
          'Browser sentence-loop playback did not remain active: '
          'playing=${state.playing}, loop=${loop?.startMs}-${loop?.endMs}, '
          'position=${state.positionMs}, duration=${state.durationMs}, '
          'samples=$positions, state=${state.processingState}.',
        );
      }
      await ready.engine.pause();
      web.window.localStorage.setItem('wp17-web-media-smoke-stage', 'played');
      _setStatus(
        'GESTURE_PLAY_AND_SENTENCE_LOOP_PASS | position=${state.positionMs}',
      );
      _mountAction('Reload while offline', _reloadOffline);
    } catch (error) {
      _setStatus('FAIL_PLAYBACK: $error');
    }
  }

  Future<void> _reloadOffline() async {
    _setStatus('OFFLINE_RELOAD_STARTED');
    web.window.location.reload();
  }

  Future<void> _playOffline(_SmokeReady ready) async {
    try {
      final before = ready.engine.snapshot.positionMs;
      await ready.engine.play();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final state = ready.engine.snapshot;
      if (state.positionMs == before ||
          state.processingState == AudioProcessingState.error) {
        throw StateError(
          'Offline playback did not advance: before=$before, '
          'after=${state.positionMs}, playing=${state.playing}, '
          'state=${state.processingState}.',
        );
      }
      await ready.engine.pause();
      final result =
          'PASS | DB=${ready.databaseName} | media=${ready.backendName} | '
          'failureRecovery=PASS | dedupe=PASS | reload=PASS | '
          'bookmark=PASS | resume=PASS | gesturePlay=PASS | '
          'sentenceLoop=PASS | offlineShell=PASS | '
          'offlineMediaPlayback=PASS';
      web.window.localStorage.setItem('wp17-web-media-smoke-result', result);
      _setStatus(result);
      web.window.localStorage.removeItem('wp17-web-media-smoke-stage');
      web.window.localStorage.removeItem('wp17-web-media-smoke-backend');
      web.window.localStorage.removeItem('wp17-web-media-smoke-run-id');
      await ready.engine.dispose();
      await ready.repository.close();
      _mountAction('Verified offline playback', () async {});
    } catch (error) {
      _setStatus('FAIL_OFFLINE_PLAYBACK: $error');
    }
  }

  void _mountAction(String label, Future<void> Function() action) {
    web.document.getElementById('wp17-smoke-action')?.remove();
    final button =
        web.document.createElement('button') as web.HTMLButtonElement;
    button
      ..id = 'wp17-smoke-action'
      ..type = 'button'
      ..textContent = label
      ..style.cssText =
          'position:fixed;z-index:99999;top:12px;right:12px;padding:16px 24px;'
          'font:16px sans-serif;color:#fff;background:#3949ab;border:0;border-radius:8px;';
    button.addEventListener(
      'click',
      ((web.Event _) => unawaited(action())).toJS,
    );
    web.document.body?.append(button);
  }

  void _setStatus(String value) {
    web.document.body?.setAttribute('data-wp17-smoke-status', value);
  }
}

enum _SmokeStage { playback, offline }

final class _SmokeReady {
  const _SmokeReady({
    required this.status,
    required this.stage,
    required this.engine,
    required this.repository,
    required this.databaseName,
    required this.backendName,
  });

  final String status;
  final _SmokeStage stage;
  final JustAudioAdapter engine;
  final SqliteMaterialRepository repository;
  final String databaseName;
  final String backendName;
}

AudioImportSource _source(String name, List<int> bytes) => AudioImportSource(
  sourceKey: 'synthetic:$name',
  name: name,
  openRead: () async* {
    yield bytes;
  },
);
