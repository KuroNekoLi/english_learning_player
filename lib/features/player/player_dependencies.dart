import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_view_model.dart';
import '../subtitles/services/subtitle_file_picker.dart';
import 'services/material_playback_loader.dart';
import 'services/player_subtitles.dart';

final materialPlaybackLoaderProvider = FutureProvider<MaterialPlaybackLoader>((
  ref,
) async {
  final scope = ref.watch(accountScopeProvider);
  final repository = ref.watch(materialRepositoryProvider.future);
  final storage = ref.watch(accountDatabaseServiceProvider.future);
  return MaterialPlaybackService(
    repository: await repository,
    storage: await storage,
    scope: scope,
  );
}, retry: (_, _) => null);

final subtitleFilePickerProvider = Provider<SubtitleFilePicker>(
  (ref) => SubtitleFilePicker(),
);

final playerSubtitlesProvider = FutureProvider<PlayerSubtitles>((ref) async {
  return PlayerSubtitles(await ref.watch(materialRepositoryProvider.future));
}, retry: (_, _) => null);
