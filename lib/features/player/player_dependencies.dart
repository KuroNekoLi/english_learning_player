import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_view_model.dart';
import 'services/material_playback_loader.dart';

final materialPlaybackLoaderProvider =
    FutureProvider.autoDispose<MaterialPlaybackLoader>((ref) async {
      final repository = await ref.watch(materialRepositoryProvider.future);
      final storage = await ref.watch(accountDatabaseServiceProvider.future);
      return MaterialPlaybackService(
        repository: repository,
        storage: storage,
        scope: ref.watch(accountScopeProvider),
      );
    }, retry: (_, _) => null);
