import 'dart:convert';

import 'package:english_learning_player/core/audio/just_audio_adapter.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/db/web_account_database_service.dart';
import 'package:english_learning_player/core/files/web_media_store.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/library/services/media_selection_import_service.dart';
import 'package:english_learning_player/features/player/services/material_playback_loader.dart';
import 'package:english_learning_player/features/subtitles/services/subtitle_import_service.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _syntheticMp3Base64 =
    'SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYzLjEuMTAyAAAAAAAAAAAAAAD/+0DAAAAAAAAAAAAAAAAAAAAAAABJbmZvAAAADwAAAAsAAAUzADc3Nzc3Nzc3N0tLS0tLS0tLS19fX19fX19fX3Nzc3Nzc3Nzc4eHh4eHh4eHh5ubm5ubm5ubm6+vr6+vr6+vr8PDw8PDw8PDw9fX19fX19fX1+vr6+vr6+vr6////////////wAAAABMYXZjNjMuMS4AAAAAAAAAAAAAAAAkBC8AAAAAAAAFMzjQzEEAAAAAAP/7EMQAAAR0E1VUkIAwpgmvNxogAgABrTlAAAFZOj1QUAgGCQHwfB8HygIAgGEQfB/UCDsTh/iDcAST9sBgOBwOAAAAAAAoiSqZFGQI6QJIFqP3hQHwExvwIpQvqBoS/CQNKgAAAZZE//sSxAKCRNgbM73QADCdg6Rln2RMwAAA+r6l/VsINGk8omcQ9mGQLgIFS/yAZBZ/rkdlD79vsAIA3/SEMMc3KDBlC1MyRhczEwtTBoAwONkxyzEGMV9B+WA5/f//9FUw0OMOHTHTgz6D//sQxAUDRQQfGA37IkCuA+LJr2hIMK8b41DOHDTrG0MJ4G01zAIGbqh1fmsGyaWhz9f0ZgoIY0aapceXuYgwzhuU51G34M8YhYRJ8KhsHRqWZqMxkCDL6QHD/1ZfR1oAAACgAxgAAF3/+xLEBIJFrB8jrPsCYJaDpPWPYEzQaAYCJo8GCQHCZPbvJk0BtmCCBYW1WMBimmBeqK5Oq/9HkP1A0MCgS9Yhac5UME0HkygkTzJzB5MEwBo6rAIyzgJmqekC1n2f7jCxAwwfMZPDOIn/+xDEBQJFAB8YDfsiQJcDZjSe8A4wnx0jSk60NIUcgwjAdTNUAwpwoHdybALNp0Ofp+gKVgSBgNsQLTmDQXGpMMHPhcAhuXYWEXOiA/h8+nU6j/VYxVgWqjChEw0eMWPTNYwwlB3TRv/7EsQHgkT8HxgN+yJAjAOm9G5sDv77NE4dMwhQeDIZBxRxGnjoAsl+zwb/T9hd0oEehDvqCGCQmbYp56YmGCCm7W3YXm7eBSmHnYLMT/9/JQACCLpWIAABKoi6SeoNERmzmHpQIqh0Wf/7EMQMAMSgHzmuaYQwkAPjga9oTScDUPXu2K6hi17P9OtoAODmYGHBbmFsG4alrmhqGBvGFyCKcRYZQ8Y06YqEBAj/1AwAAggcBwMAACkLNxS2BgWmO8NnyVoSm4wM/LXm2sv6R3+///sSxBECRIgdN6T3QHCBg6e0zbBW3fpU2oFs9w/A4BQE47BOLAUREw2tkgVhPQo0vt2/79N4/IoABAoUQAMAABYBWRIIQSHBkFOR/2xcFDkxV+mIs1tGe/p///ax0MFmaEHFWmF4GAaq//sQxBiAxIQdNaT3QHCPA+OBr2hNbLxqYBhGF6B6cRUZQ8Ys6YaIDAj/1C0wQLMDGDCDcxuAMF4bkzC97TL0GxME0HIYdJkgF6dbQRU0GeM/oSAMttstrjcbi6VC0DkbA37L3nds0zT/+xLEHgBEuB8aDfsiYPaOKfayYAbLJYGyhrkU3oHCydwCAAgWAAjLvYhyAAQ55MnbE78Y92xMmOBAMbVKAAAsEYrFgwEAAAAAAATVMlzLv+Asl3Y7/zT5OJ57Zd/htIWaMk8BhAEw1yv/+xDEFgAIaIFRuZgAEAAANIOAAAThdMc8TQVa0a/BuINlD+C+E5/+VC6XjGpMQU1FNC4wqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqg==';

void main() => runApp(const WebMediaImportSmokeApp());

final class WebMediaImportSmokeApp extends StatelessWidget {
  const WebMediaImportSmokeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WP-17 media smoke',
    home: Scaffold(
      appBar: AppBar(title: const Text('WP-17 Web media smoke')),
      body: Center(
        child: FutureBuilder<String>(
          future: _runSmoke(),
          builder: (context, snapshot) => Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              snapshot.hasError
                  ? 'FAIL: ${snapshot.error}'
                  : snapshot.data ?? 'RUNNING',
              key: const ValueKey('webMediaSmokeResult'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<String> _runSmoke() async {
  const runIdKey = 'wp17-web-media-smoke-run-id';
  const importedKey = 'wp17-web-media-smoke-imported';
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
  if (web.window.localStorage.getItem(importedKey) != 'true') {
    final syntheticMp3 = base64.decode(_syntheticMp3Base64);
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
    if (result.importedMaterials.length != 1 || result.subtitlesImported != 2) {
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
    web.window.localStorage.setItem(
      backendKey,
      mediaStore.lastWriteBackend?.name ?? 'unknown',
    );
    await repository.close();
    web.window.localStorage.setItem(importedKey, 'true');
    web.window.location.reload();
    return 'RELOADING';
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
  final engine = JustAudioAdapter();
  await engine.load(bundle.source);
  final durationMs = engine.snapshot.durationMs;
  if (durationMs == null || durationMs <= 0) {
    throw StateError('The Web audio decoder did not report a duration.');
  }
  await engine.seekTo(Duration(milliseconds: durationMs ~/ 2));
  if (engine.snapshot.positionMs <= 0) {
    throw StateError('Web seek did not update the playback position.');
  }
  await engine.unload();
  await engine.dispose();
  await repository.close();
  web.window.localStorage.removeItem(importedKey);
  final mediaBackend = web.window.localStorage.getItem(backendKey) ?? 'unknown';
  web.window.localStorage.removeItem(backendKey);
  web.window.localStorage.removeItem(runIdKey);
  final status =
      'PASS | DB=${opened.chosenImplementation.name} | '
      'media=$mediaBackend | '
      'audio=1 | subtitleTracks=2 | browserReload=PASS | '
      'dedupe=PASS | decode=PASS | seek=PASS';
  // ignore: avoid_print
  print('WP17_WEB_MEDIA_SMOKE $status');
  return status;
}

AudioImportSource _source(String name, List<int> bytes) => AudioImportSource(
  sourceKey: 'synthetic:$name',
  name: name,
  openRead: () async* {
    yield bytes;
  },
);
