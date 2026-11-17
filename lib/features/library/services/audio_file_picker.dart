import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../domain/audio_import_source.dart';

abstract interface class AudioFilePicker {
  Future<List<AudioImportSource>> pickMediaFiles();
}

final class NativeAudioFilePicker implements AudioFilePicker {
  static const _audioFiles = XTypeGroup(
    label: 'Media and subtitles',
    extensions: ['m4a', 'mp3', 'srt'],
    mimeTypes: ['audio/mp4', 'audio/mpeg', 'application/x-subrip'],
    uniformTypeIdentifiers: [
      'public.mpeg-4-audio',
      'public.mp3',
      'com.subrip.subrip',
    ],
  );

  @override
  Future<List<AudioImportSource>> pickMediaFiles() async =>
      (await openFiles(acceptedTypeGroups: [_audioFiles]))
          .map(
            (file) => AudioImportSource(
              sourceKey: sha256.convert(utf8.encode(file.path)).toString(),
              name: file.name,
              openRead: file.openRead,
            ),
          )
          .toList(growable: false);
}
