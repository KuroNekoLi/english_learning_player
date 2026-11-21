import 'package:uuid/uuid.dart';

import '../../../core/files/audio_file_type.dart';
import '../../../core/files/media_store.dart';
import '../domain/audio_import_source.dart';
import '../material_repository.dart';

final class AudioImportService {
  AudioImportService({
    required MaterialRepository repository,
    required MediaStore mediaStore,
    Uuid uuid = const Uuid(),
  }) : _repository = repository,
       _mediaStore = mediaStore,
       _uuid = uuid;

  final MaterialRepository _repository;
  final MediaStore _mediaStore;
  final Uuid _uuid;

  Future<ImportResult> importAudio(
    AudioImportSource source, {
    void Function(int bytesCopied, int? totalBytes)? onProgress,
  }) async {
    AudioFileType.fromName(source.name);
    var bytesCopied = 0;
    final trackedSource = AudioImportSource(
      sourceKey: source.sourceKey,
      name: source.name,
      byteLength: source.byteLength,
      openRead: () async* {
        await for (final chunk in source.openRead()) {
          bytesCopied += chunk.length;
          onProgress?.call(bytesCopied, source.byteLength);
          yield chunk;
        }
      },
    );
    final stored = await _mediaStore.copyAndHash(trackedSource);
    final now = DateTime.now().toUtc();
    final result = await _repository.insertAudio(
      asset: StoredAudioAsset(
        id: _uuid.v4(),
        sha256: stored.sha256,
        byteLength: stored.byteLength,
        mediaType: stored.mediaType,
        relativePath: stored.relativePath,
      ),
      sourceKey: source.sourceKey,
      title: _titleFromName(source.name),
      materialId: _uuid.v4(),
      createdAt: now,
    );
    return ImportResult(
      material: result.material,
      wasDuplicate: result.wasDuplicate,
    );
  }

  String _titleFromName(String name) {
    final separator = name.lastIndexOf('.');
    return separator > 0 ? name.substring(0, separator) : name;
  }
}

final class ImportResult {
  const ImportResult({required this.material, required this.wasDuplicate});

  final LearningMaterial material;
  final bool wasDuplicate;
}
