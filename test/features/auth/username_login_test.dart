import 'package:english_learning_player/features/auth/username_login.dart';
import 'package:english_learning_player/core/sync/sync_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the approved username to a Firebase email credential', () {
    expect(normalizeLoginUsername('  KURONEKO_LI '), 'kuroneko_li');
    expect(
      loginEmail('kuroneko_li', 'english-learning-player-auth'),
      'kuroneko_li@english-learning-player-auth.firebaseapp.com',
    );
    expect(isReadOnlyLoginUsername('kuroneko_li'), isTrue);
    expect(isReadOnlyLoginUsername('other_account'), isFalse);
  });

  test(
    'rejects username characters that cannot safely form an email alias',
    () {
      expect(
        () => normalizeLoginUsername('name@example.com'),
        throwsA(isA<SyncFailure>()),
      );
      expect(() => normalizeLoginUsername('ab'), throwsA(isA<SyncFailure>()));
    },
  );
}
