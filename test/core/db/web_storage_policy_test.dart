import 'package:english_learning_player/core/db/web_storage_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('webStorageModeAllowsWrites', () {
    test('allows persistent modes coordinated across tabs', () {
      for (final mode in ['opfsShared', 'opfsLocks', 'sharedIndexedDb']) {
        expect(webStorageModeAllowsWrites(mode), isTrue, reason: mode);
      }
    });

    test('blocks volatile or uncoordinated modes', () {
      for (final mode in ['unsafeIndexedDb', 'inMemory', 'unknown']) {
        expect(webStorageModeAllowsWrites(mode), isFalse, reason: mode);
      }
    });
  });
}
