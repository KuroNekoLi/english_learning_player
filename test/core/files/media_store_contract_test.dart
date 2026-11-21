import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/files/media_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media keys are resolved only inside the matching account scope', () {
    final scope = AccountScope('media-owner');
    final path = 'media/${scope.storageKey}/lesson.m4a';

    expect(mediaObjectKey(scope, path), 'lesson.m4a');
    expect(
      () => mediaObjectKey(AccountScope('other-owner'), path),
      throwsFormatException,
    );
    expect(
      () => mediaObjectKey(scope, '$path/../../outside.m4a'),
      throwsFormatException,
    );
  });
}
