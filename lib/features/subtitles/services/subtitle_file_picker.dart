import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../library/domain/audio_import_source.dart';

final class SubtitleFilePicker {
  static const _srtFiles = XTypeGroup(
    label: 'SubRip subtitles',
    extensions: ['srt'],
  );
  static const _androidSrtFiles = XTypeGroup(
    label: 'SubRip subtitles',
    extensions: ['srt'],
    mimeTypes: [
      'application/x-subrip',
      'text/plain',
      'application/octet-stream',
    ],
  );

  Future<AudioImportSource?> pickSubtitle() async {
    // iOS document providers can report an unregistered SRT as generic data.
    // The importer validates its extension and contents after selection.
    final file = await openFile(
      acceptedTypeGroups: kIsWeb
          ? const [_srtFiles]
          : switch (defaultTargetPlatform) {
              TargetPlatform.iOS => const [
                XTypeGroup(uniformTypeIdentifiers: ['public.data']),
              ],
              TargetPlatform.android => const [_androidSrtFiles],
              _ => const [_srtFiles],
            },
    );
    if (file == null) return null;
    return AudioImportSource(
      sourceKey: sha256.convert(utf8.encode(file.path)).toString(),
      name: file.name,
      openRead: file.openRead,
    );
  }
}
