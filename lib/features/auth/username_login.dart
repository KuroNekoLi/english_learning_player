import '../../../core/sync/sync_contracts.dart';

const readOnlyLoginProject = 'english-learning-player-auth';

String normalizeLoginUsername(String value) {
  final username = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(username)) {
    throw const SyncFailure(SyncFailureKind.invalidData, 'invalid_username');
  }
  return username;
}

String loginEmail(String username, String project) =>
    '${normalizeLoginUsername(username)}@$project.firebaseapp.com';

bool isReadOnlyLoginUsername(String username) =>
    normalizeLoginUsername(username) == 'kuroneko_li';

bool isSupportedReadOnlyLoginProject(String project) =>
    project == readOnlyLoginProject;
