import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../../library/domain/audio_import_source.dart';

final class SubtitleFilePicker {
  static const _srtFiles = XTypeGroup(
    label: 'SubRip subtitles',
    extensions: ['srt'],
    mimeTypes: ['application/x-subrip'],
  );

  Future<AudioImportSource?> pickSubtitle() async {
    final file = await openFile(acceptedTypeGroups: [_srtFiles]);
    if (file == null) return null;
    return AudioImportSource(
      sourceKey: sha256.convert(utf8.encode(file.path)).toString(),
      name: file.name,
      openRead: file.openRead,
    );
  }
}
