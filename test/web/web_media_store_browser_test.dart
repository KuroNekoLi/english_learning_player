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
}
