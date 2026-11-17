import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_view_model.dart';
import 'services/material_playback_loader.dart';

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
