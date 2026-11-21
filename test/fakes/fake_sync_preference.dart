import 'package:english_learning_player/features/sync/sync_preference.dart';

final class FakeSyncPreferencePersistence implements SyncPreferencePersistence {
  final choices = <SyncPreferenceKey, SyncPreference>{};

  @override
  Future<SyncPreference> read(SyncPreferenceKey key) async =>
      choices[key] ?? SyncPreference.undecided;

  @override
  Future<void> write(SyncPreferenceKey key, SyncPreference choice) async {
    choices[key] = choice;
  }
}
