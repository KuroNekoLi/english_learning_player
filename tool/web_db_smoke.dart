import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/core/db/web_account_database_service.dart';
import 'package:english_learning_player/features/progress/data/sqlite_progress_repository.dart';
import 'package:material_ui/material_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WebDatabaseSmokeApp());
}

final class WebDatabaseSmokeApp extends StatelessWidget {
  const WebDatabaseSmokeApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'Web DB smoke', home: WebDatabaseSmokePage());
}

final class WebDatabaseSmokePage extends StatefulWidget {
  const WebDatabaseSmokePage({super.key});

  @override
  State<WebDatabaseSmokePage> createState() => _WebDatabaseSmokePageState();
}

final class _WebDatabaseSmokePageState extends State<WebDatabaseSmokePage> {
  late final Future<List<_ScopeSmokeResult>> _results = _openScopes();

  Future<List<_ScopeSmokeResult>> _openScopes() async {
    const service = WebAccountDatabaseService();
    final results = <_ScopeSmokeResult>[];

    for (final ownerId in ['local-default', 'web-smoke-secondary']) {
      final scope = AccountScope(ownerId);
      final opened = await service.open(scope);
      String? deviceId;
      if (opened.storageIsSafeForWrites) {
        deviceId = await SqliteProgressRepository(
          scope: scope,
          db: opened.database,
        ).deviceId();
      }
      results.add(
        _ScopeSmokeResult(
          ownerId: ownerId,
          databaseName: opened.databaseName,
          implementation: opened.chosenImplementation.name,
          missingFeatures: opened.missingFeatures
              .map((feature) => feature.name)
              .toList(),
          storageIsSafeForWrites: opened.storageIsSafeForWrites,
          deviceId: deviceId,
          database: opened.database,
        ),
      );
    }

    return results;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('WP-17 Drift Web smoke')),
    body: FutureBuilder<List<_ScopeSmokeResult>>(
      future: _results,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SelectableText('OPEN_FAILED: ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final results = snapshot.requireData;
        final modes = results.map((result) => result.implementation).toSet();
        final allWritable = results.every(
          (result) => result.storageIsSafeForWrites,
        );
        final idsAreIsolated = results[0].deviceId != results[1].deviceId;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('ORIGIN: ${Uri.base.origin}'),
            Text('STORAGE_MODE: ${modes.join(', ')}'),
            Text('SAFE_WRITES: $allWritable'),
            Text('ACCOUNT_ISOLATION: $idsAreIsolated'),
            const Text('Reload this URL and compare both device IDs.'),
            const Text(
              'Open this URL in a second tab to verify concurrent access.',
            ),
            for (final result in results) ...[
              const Divider(),
              Text('OWNER: ${result.ownerId}'),
              Text('DATABASE: ${result.databaseName}'),
              Text('MODE: ${result.implementation}'),
              Text('MISSING_FEATURES: ${result.missingFeatures.join(', ')}'),
              Text('WRITE_CHECK: ${result.storageIsSafeForWrites}'),
              Text('DEVICE_ID: ${result.deviceId ?? 'not written'}'),
            ],
            if (!allWritable)
              const Text(
                'Persistent writes are disabled because this browser mode '
                'does not coordinate multiple tabs safely.',
              ),
          ],
        );
      },
    ),
  );
}

final class _ScopeSmokeResult {
  const _ScopeSmokeResult({
    required this.ownerId,
    required this.databaseName,
    required this.implementation,
    required this.missingFeatures,
    required this.storageIsSafeForWrites,
    required this.deviceId,
    required this.database,
  });

  final String ownerId;
  final String databaseName;
  final String implementation;
  final List<String> missingFeatures;
  final bool storageIsSafeForWrites;
  final String? deviceId;
  // Hold open for the lifetime of this smoke page, as the real provider does.
  final LocalDatabase database;
}
