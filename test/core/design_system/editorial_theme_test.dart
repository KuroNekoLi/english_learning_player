import 'dart:convert';
import 'dart:io';

import 'package:english_learning_player/core/design_system/editorial_theme.dart';
import 'package:english_learning_player/core/design_system/editorial_tokens.dart';
import 'package:english_learning_player/core/design_system/theme_preference.dart';
import 'package:english_learning_player/core/design_system/theme_mode_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in {
    'light': EditorialColors.light,
    'dark': EditorialColors.dark,
  }.entries) {
    test('${entry.key} token and contrast contract', () {
      final c = entry.value;
      final actual = {
        'background': c.background,
        'surface': c.surface,
        'textPrimary': c.textPrimary,
        'textSecondary': c.textSecondary,
        'primary': c.primary,
        'onPrimary': c.onPrimary,
        'activeSubtitle': c.activeSubtitle,
        'divider': c.divider,
        'controlOutline': c.controlOutline,
        'wordHighlight': c.wordHighlight,
        'onWordHighlight': c.onWordHighlight,
        'error': c.error,
        'focus': c.focus,
      };
      final raw = jsonDecode(
        File('docs/design-system/editorial-tokens.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final expected = raw['color'][entry.key] as Map<String, dynamic>;
      for (final pair in actual.entries) {
        expect(
          '#${(pair.value.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}',
          expected[pair.key],
        );
      }
      for (final bg in [c.background, c.surface, c.activeSubtitle]) {
        expect(editorialContrast(c.textPrimary, bg), greaterThanOrEqualTo(4.5));
        expect(
          editorialContrast(c.textSecondary, bg),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          editorialContrast(c.controlOutline, bg),
          greaterThanOrEqualTo(3),
        );
        for (final alpha in [.5, .65, .8, 1.0]) {
          expect(
            editorialContrast(
              readableTranslation(c.textSecondary, bg, alpha),
              bg,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(
        editorialContrast(c.onPrimary, c.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        editorialContrast(c.onWordHighlight, c.wordHighlight),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
  test(
    'theme mode persists and restores in a new provider container',
    () async {
      final first = ProviderContainer();
      expect(
        await first.read(themePreferenceProvider.future),
        ThemeMode.system,
      );
      await first.read(themePreferenceProvider.notifier).select(ThemeMode.dark);
      expect(first.read(themePreferenceProvider).value, ThemeMode.dark);
      first.dispose();
      final second = ProviderContainer();
      addTearDown(second.dispose);
      expect(await second.read(themePreferenceProvider.future), ThemeMode.dark);
    },
  );
  test('unknown saved value falls back to system', () async {
    SharedPreferences.setMockInitialValues({editorialThemeKey: 'unsupported'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      await container.read(themePreferenceProvider.future),
      ThemeMode.system,
    );
  });
  testWidgets(
    'theme selection updates existing app without replacing its page',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              theme: EditorialTheme.light,
              darkTheme: EditorialTheme.dark,
              themeMode:
                  ref.watch(themePreferenceProvider).asData?.value ??
                  ThemeMode.system,
              home: const Scaffold(body: ThemeModeTile()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切換外觀'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(ThemeModeTile))).brightness,
        Brightness.dark,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(editorialThemeKey),
        'dark',
      );
    },
  );
}
