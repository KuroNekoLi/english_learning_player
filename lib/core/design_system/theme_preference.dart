import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const editorialThemeKey = 'appearance.theme_mode.v1';
final themePreferenceProvider =
    AsyncNotifierProvider<ThemePreference, ThemeMode>(ThemePreference.new);

final class ThemePreference extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(editorialThemeKey);
      return ThemeMode.values.where((m) => m.name == saved).firstOrNull ??
          ThemeMode.system;
    } catch (_) {
      return ThemeMode.system;
    }
  }

  bool _saving = false;
  Future<void> select(ThemeMode mode) async {
    if (_saving) return;
    _saving = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(editorialThemeKey, mode.name)) {
        throw StateError('Unable to save theme');
      }
      state = AsyncData(mode);
    } finally {
      _saving = false;
    }
  }
}
