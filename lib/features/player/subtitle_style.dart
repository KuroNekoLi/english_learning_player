import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local reading preferences, independent of the selected material.
final class SubtitleStyle {
  const SubtitleStyle({
    this.englishSize = 19,
    this.chineseSize = 15,
    this.lineHeight = 1.45,
    this.spacing = 12,
    this.translationOpacity = 1,
    this.readingWidth = 900,
    this.highlightSavedWords = true,
  });

  final double englishSize,
      chineseSize,
      lineHeight,
      spacing,
      translationOpacity,
      readingWidth;
  final bool highlightSavedWords;

  SubtitleStyle copyWith({
    double? englishSize,
    double? chineseSize,
    double? lineHeight,
    double? spacing,
    double? translationOpacity,
    double? readingWidth,
    bool? highlightSavedWords,
  }) => SubtitleStyle(
    englishSize: englishSize ?? this.englishSize,
    chineseSize: chineseSize ?? this.chineseSize,
    lineHeight: lineHeight ?? this.lineHeight,
    spacing: spacing ?? this.spacing,
    translationOpacity: translationOpacity ?? this.translationOpacity,
    readingWidth: readingWidth ?? this.readingWidth,
    highlightSavedWords: highlightSavedWords ?? this.highlightSavedWords,
  );

  Map<String, Object> toJson() => {
    'englishSize': englishSize,
    'chineseSize': chineseSize,
    'lineHeight': lineHeight,
    'spacing': spacing,
    'translationOpacity': translationOpacity,
    'readingWidth': readingWidth,
    'highlightSavedWords': highlightSavedWords,
  };

  factory SubtitleStyle.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback, double min, double max) {
      final value = json[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    return SubtitleStyle(
      englishSize: read('englishSize', 19, 14, 32),
      chineseSize: read('chineseSize', 15, 12, 26),
      lineHeight: read('lineHeight', 1.45, 1.2, 2),
      spacing: read('spacing', 12, 4, 32),
      translationOpacity: read('translationOpacity', 1, 0.5, 1),
      readingWidth: read('readingWidth', 900, 480, 1200),
      highlightSavedWords: json['highlightSavedWords'] != false,
    );
  }
}

const _styleKey = 'player.subtitle_style.v1';

final subtitleStyleProvider = FutureProvider<SubtitleStyle>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_styleKey);
  if (raw == null) return const SubtitleStyle();
  try {
    return SubtitleStyle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return const SubtitleStyle();
  }
});

Future<void> saveSubtitleStyle(SubtitleStyle value) async {
  final prefs = await SharedPreferences.getInstance();
  if (!await prefs.setString(_styleKey, jsonEncode(value.toJson()))) {
    throw StateError('Unable to save subtitle style');
  }
}
