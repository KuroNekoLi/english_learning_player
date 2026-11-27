import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_view_model.dart';
import '../progress/progress_dependencies.dart';
import '../library/material_repository.dart';

final recentPlaybackProvider = FutureProvider.autoDispose<RecentPlayback?>((
  ref,
) async {
  final progress = await ref.watch(progressRepositoryProvider.future);
  final recent = await progress.mostRecentlyPlayed();
  if (recent == null) return null;
  final materials = await ref.watch(libraryViewModelProvider.future);
  for (final material in materials) {
    if (material.id == recent.materialId) {
      return RecentPlayback(material: material, positionMs: recent.positionMs);
    }
  }
  return null;
});

final class RecentPlayback {
  const RecentPlayback({required this.material, required this.positionMs});

  final LearningMaterial material;
  final int positionMs;
}
