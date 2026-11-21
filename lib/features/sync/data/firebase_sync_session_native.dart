import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/firebase_identity_session.dart';
import '../../auth/firebase_session_controller.dart';

final firebaseMediaEndpointProvider = firebaseEndpointProvider;

FirebaseIdentitySession? watchSyncSession(Ref ref) {
  ref.watch(firebaseSessionProvider.select((state) => state.uid));
  return ref.watch(firebaseAuthSessionProvider);
}

bool isCurrentSyncAccount(Ref ref, String uid) =>
    ref.read(firebaseSessionProvider).uid == uid &&
    ref.read(firebaseAuthSessionProvider)?.uid == uid;
