import 'package:material_ui/material_ui.dart';

import '../material_repository.dart';

Future<LearningMaterial?> pickLibraryMaterial(
  BuildContext context, {
  required String title,
  required List<LearningMaterial> materials,
  required String emptyMessage,
}) => showDialog<LearningMaterial>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: materials.isEmpty
        ? Text(emptyMessage)
        : SizedBox(
            width: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: materials.length,
              itemBuilder: (context, index) {
                final material = materials[index];
                return ListTile(
                  leading: const Icon(Icons.headphones_outlined),
                  title: Text(material.title),
                  onTap: () => Navigator.of(context).pop(material),
                );
              },
            ),
          ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(materials.isEmpty ? '關閉' : '取消'),
      ),
    ],
  ),
);
