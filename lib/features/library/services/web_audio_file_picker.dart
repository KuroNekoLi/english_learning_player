import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../domain/audio_import_source.dart';
import 'audio_file_picker.dart';

final class WebAudioFilePicker implements AudioFilePicker {
  static const _selectedFiles = XTypeGroup(
    label: 'Audio and subtitle files',
    extensions: ['m4a', 'mp3', 'srt'],
    mimeTypes: ['audio/mp4', 'audio/mpeg', 'application/x-subrip'],
  );

  @override
  Future<List<AudioImportSource>> pickMediaFiles() async {
    final files = await openFiles(acceptedTypeGroups: [_selectedFiles]);
    final sources = <AudioImportSource>[];
    for (final file in files) {
      final length = await file.length();
      final lastModified = await file.lastModified();
      sources.add(
        AudioImportSource(
          sourceKey: sha256
              .convert(
                utf8.encode(
                  '${file.name}|$length|${lastModified.millisecondsSinceEpoch}',
                ),
              )
              .toString(),
          name: file.name,
          openRead: file.openRead,
          byteLength: length,
        ),
      );
    }
    return sources;
  }
}
