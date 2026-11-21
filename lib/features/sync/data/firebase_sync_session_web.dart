import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_endpoint.dart';
import '../../auth/data/firebase_identity_session.dart';
import '../../auth/web/web_firebase_session_controller.dart';

final firebaseMediaEndpointProvider = Provider<FirebaseEndpoint?>(
  (ref) => FirebaseEndpoint.fromEnvironment(),
);

FirebaseIdentitySession watchSyncSession(Ref ref) =>
    ref.watch(webFirebaseIdentitySessionProvider);

bool isCurrentSyncAccount(Ref ref, String uid) =>
    ref.read(webFirebaseSessionProvider).uid == uid &&
    ref.read(webFirebaseAuthPortProvider).currentUid == uid;
