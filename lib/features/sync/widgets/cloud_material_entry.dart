import 'package:flutter/material.dart';

import '../../../core/sync/sync_contracts.dart';
import '../../progress/domain/progress_models.dart';

final class CloudMaterialEntry extends StatelessWidget {
  const CloudMaterialEntry({
    super.key,
    required this.material,
    required this.conflicts,
    required this.isLocal,
    required this.onDownload,
    required this.onResolve,
  });

  final CloudMaterialMetadata material;
  final List<ProgressCandidate> conflicts;
  final bool isLocal;
  final VoidCallback? onDownload;
  final ValueChanged<ProgressCandidate>? onResolve;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        title: Text(material.title),
        trailing: TextButton(
          onPressed: onDownload,
          child: Text(isLocal ? '重新下載' : '下載'),
        ),
      ),
      for (final candidate in conflicts)
        TextButton(
          onPressed: onResolve == null ? null : () => onResolve!(candidate),
          child: Text('選擇「${material.title}」的續播位置'),
        ),
    ],
  );
}
