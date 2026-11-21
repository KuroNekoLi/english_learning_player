@TestOn('browser')
library;

import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/files/web_media_store.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'browser-private media survives service recreation and yields a Blob URL',
    () async {
      final scope = AccountScope(
        'browser-media-${DateTime.now().microsecondsSinceEpoch}',
      );
      const bytes = [0, 1, 2, 3, 250, 255];
      final store = WebMediaStore(scope);
      final imported = await store.copyAndHash(
        AudioImportSource(
          sourceKey: 'browser-synthetic-media',
          name: 'synthetic.mp3',
          openRead: () async* {
            yield bytes;
          },
        ),
      );
      expect(store.lastWriteBackend, WebMediaBackend.opfs);

      final reopened = await WebMediaStore(scope).open(imported.relativePath);
      expect(reopened, isNotNull);
      expect(reopened!.uri.scheme, 'blob');
      await reopened.release?.call();
    },
  );

  test('rejects media paths from a different browser account scope', () async {
    final owner = AccountScope('browser-owner');
    final other = AccountScope('browser-other');
    await expectLater(
      WebMediaStore(other).open('media/${owner.storageKey}/shared.m4a'),
      throwsFormatException,
    );
  });

  test('uses the IndexedDB Blob fallback when OPFS writes fail', () async {
    final scope = AccountScope(
      'browser-fallback-${DateTime.now().microsecondsSinceEpoch}',
    );
    final store = WebMediaStore.forTesting(
      scope,
      beforeWrite: (backend) async {
        if (backend == WebMediaBackend.opfs) {
          throw StateError('QuotaExceededError');
        }
      },
    );
    final imported = await store.copyAndHash(
      _source('fallback.mp3', [4, 5, 6]),
    );

    expect(store.lastWriteBackend, WebMediaBackend.indexedDb);
    final restored = await WebMediaStore(scope).open(imported.relativePath);
    expect(restored, isNotNull);
    expect(restored!.uri.scheme, 'blob');
    await restored.release?.call();
  });

  test('a failed IndexedDB write can be retried successfully', () async {
    final scope = AccountScope(
      'browser-retry-${DateTime.now().microsecondsSinceEpoch}',
    );
    final failedStore = WebMediaStore.forTesting(
      scope,
      beforeWrite: (_) async => throw StateError('simulated quota failure'),
    );
    await expectLater(
      failedStore.copyAndHash(_source('retry.mp3', [7, 8, 9])),
      throwsStateError,
    );

    final retry = WebMediaStore.forTesting(scope, forceIndexedDb: true);
    final imported = await retry.copyAndHash(_source('retry.mp3', [7, 8, 9]));
    expect(retry.lastWriteBackend, WebMediaBackend.indexedDb);
    final restored = await WebMediaStore(scope).open(imported.relativePath);
    expect(restored, isNotNull);
    await restored!.release?.call();
  });

  test(
    'an interrupted source stream can be retried without stale media',
    () async {
      final scope = AccountScope(
        'browser-interrupted-${DateTime.now().microsecondsSinceEpoch}',
      );
      final source = AudioImportSource(
        sourceKey: 'interrupted-source',
        name: 'interrupted.mp3',
        openRead: () async* {
          yield [1, 2, 3];
          throw StateError('simulated interrupted read');
        },
      );
      await expectLater(
        WebMediaStore(scope).copyAndHash(source),
        throwsStateError,
      );
      final retry = await WebMediaStore(
        scope,
      ).copyAndHash(_source('interrupted.mp3', [1, 2, 3]));
      expect(await WebMediaStore(scope).open(retry.relativePath), isNotNull);
    },
  );
}

AudioImportSource _source(String name, List<int> bytes) => AudioImportSource(
  sourceKey: 'source:$name',
  name: name,
  openRead: () async* {
    yield bytes;
  },
);
