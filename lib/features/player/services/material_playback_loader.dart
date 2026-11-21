import '../../../core/audio/audio_engine.dart';
import '../../../core/db/account_database_service.dart';
import '../../../core/db/account_scope.dart';
import '../../library/material_repository.dart';
import '../../subtitles/domain/subtitle_models.dart';
import '../../subtitles/domain/subtitle_timeline.dart';

abstract interface class MaterialPlaybackLoader {
  Future<MaterialPlaybackBundle> load(LearningMaterial material);
}

final class MaterialPlaybackBundle {
  MaterialPlaybackBundle({
    required this.material,
    required this.source,
    required List<SubtitleTrack> subtitleTracks,
  }) : subtitleTracks = List.unmodifiable(subtitleTracks);

  final LearningMaterial material;
  final MediaSource source;
  final List<SubtitleTrack> subtitleTracks;

  late final SubtitleTimeline? timeline = switch (englishTrack) {
    final english? => SubtitleTimeline(english, chineseTrack),
    null => null,
  };

  SubtitleTrack? get englishTrack => _selectedTrack('en');
  SubtitleTrack? get chineseTrack => _selectedTrack('zh');

  SubtitleTrack? _selectedTrack(String language) {
    for (final track in subtitleTracks) {
      final tag = track.languageTag.toLowerCase();
      if (track.isSelected && tag.startsWith(language)) return track;
    }
    return null;
  }
}

final class MaterialPlaybackService implements MaterialPlaybackLoader {
  const MaterialPlaybackService({
    required MaterialRepository repository,
    required AccountDatabaseService storage,
    required AccountScope scope,
  }) : _repository = repository,
       _storage = storage,
       _scope = scope;

  final MaterialRepository _repository;
  final AccountDatabaseService _storage;
  final AccountScope _scope;

  @override
  Future<MaterialPlaybackBundle> load(LearningMaterial material) async {
    if (material.ownerId != _scope.ownerId) {
      throw ArgumentError.value(material.ownerId, 'material.ownerId');
    }
    final asset = await _repository.audioAssetForMaterial(material.id);
    if (asset == null || asset.id != material.audioAssetId) {
      throw const MaterialPlaybackException('教材音訊資料不存在');
    }
    final file = _storage.resolveMediaFile(_scope, asset.relativePath);
    if (!await file.exists()) {
      throw const MaterialPlaybackException('教材音訊檔案遺失');
    }
    final tracks = await _repository.listSubtitleTracks(material.id);
    return MaterialPlaybackBundle(
      material: material,
      source: MediaSource(materialId: material.id, uri: file.uri),
      subtitleTracks: tracks,
    );
  }
}

final class MaterialPlaybackException implements Exception {
  const MaterialPlaybackException(this.message);

  final String message;
}
