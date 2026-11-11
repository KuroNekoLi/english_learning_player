import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'material_repository.dart';

final materialRepositoryProvider = Provider<MaterialRepository>(
  (ref) => const _EmptyMaterialRepository(),
);

final libraryViewModelProvider = FutureProvider<List<LearningMaterial>>((
  ref,
) async {
  final repository = ref.watch(materialRepositoryProvider);
  return List.unmodifiable(await repository.listMaterials());
}, retry: (_, _) => null);

final class _EmptyMaterialRepository implements MaterialRepository {
  const _EmptyMaterialRepository();

  @override
  Future<List<LearningMaterial>> listMaterials() async => const [];
}
