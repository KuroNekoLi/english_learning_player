import 'package:english_learning_player/features/auth/link_read_only_username_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains why read-only account setup cannot be submitted', (
    tester,
  ) async {
    await _pumpDialog(tester);

    await tester.tap(find.byKey(const ValueKey('linkUsernameSubmit')));
    await tester.pump();
    expect(find.text('密碼至少需要 6 個字元。'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('linkPassword')),
      'temporary1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('linkPasswordConfirm')),
      'temporary2',
    );
    await tester.tap(find.byKey(const ValueKey('linkUsernameSubmit')));
    await tester.pump();
    expect(find.text('兩次輸入的密碼不一致。'), findsOneWidget);
  });

  testWidgets('returns credentials when the password is valid and confirmed', (
    tester,
  ) async {
    late Future<({String username, String password})?> result;
    await _pumpDialog(tester, onOpened: (opened) => result = opened);
    await tester.enterText(
      find.byKey(const ValueKey('linkPassword')),
      'temporary1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('linkPasswordConfirm')),
      'temporary1',
    );
    await tester.tap(find.byKey(const ValueKey('linkUsernameSubmit')));
    await tester.pumpAndSettle();

    expect(await result, (username: 'kuroneko_li', password: 'temporary1'));
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  void Function(Future<({String username, String password})?> result)? onOpened,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              final result = showDialog<({String username, String password})>(
                context: context,
                builder: (_) => const LinkReadOnlyUsernameDialog(),
              );
              onOpened?.call(result);
            },
            child: const Text('開啟設定'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('開啟設定'));
  await tester.pumpAndSettle();
}
