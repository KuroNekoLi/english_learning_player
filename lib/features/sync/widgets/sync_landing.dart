import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_sync_dependencies.dart';
import '../firebase_sync_view_model.dart';
import '../sync_preference.dart';

/// Keeps the first sync choice on the account screen after the sign-in route is
/// replaced. The media runner lives with the app, independently of this screen.
final class SyncLanding extends ConsumerStatefulWidget {
  const SyncLanding({
    super.key,
    required this.uid,
    required this.library,
    required this.accountPage,
  });

  final String? uid;
  final Widget library;
  final Widget accountPage;

  @override
  ConsumerState<SyncLanding> createState() => _SyncLandingState();
}

final class _SyncLandingState extends ConsumerState<SyncLanding>
    with WidgetsBindingObserver {
  static const _queueInterval = Duration(seconds: 5);
  static const _catalogInterval = Duration(minutes: 2);
  Timer? _timer;
  DateTime? _nextCatalog;
  SyncPreferenceKey? _key;
  bool _asking = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_queueInterval, (_) => unawaited(_tick()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _nextCatalog = null;
      unawaited(_tick());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _tick() async {
    final key = _key;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        _running ||
        key == null ||
        (lifecycle == AppLifecycleState.paused ||
            lifecycle == AppLifecycleState.detached ||
            (!kIsWeb && lifecycle == AppLifecycleState.hidden)) ||
        ref.read(syncPreferenceProvider(key)).asData?.value !=
            SyncPreference.enabled) {
      return;
    }
    _running = true;
    try {
      final now = DateTime.now();
      final refresh = _nextCatalog == null || !now.isBefore(_nextCatalog!);
      if (refresh) _nextCatalog = now.add(_catalogInterval);
      await ref
          .read(firebaseSyncViewModelProvider.notifier)
          .syncAutomatically(refreshCatalog: refresh);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final endpoint = ref.watch(firebaseMediaEndpointProvider);
    if (uid == null || endpoint == null || !endpoint.isMediaSyncConfigured) {
      _key = null;
      return widget.library;
    }
    final key = _key = (uid: uid, project: endpoint.project);
    final provider = syncPreferenceProvider(key);
    final preference = ref.watch(provider);
    ref.watch(firebaseSyncViewModelProvider.select((_) => null));
    ref.listen(provider, (before, after) {
      if (after.asData?.value == SyncPreference.enabled &&
          before?.asData?.value != SyncPreference.enabled) {
        _nextCatalog = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_tick()));
      } else if (after.asData?.value == SyncPreference.disabled &&
          before?.asData?.value == SyncPreference.enabled) {
        ref
            .read(firebaseSyncViewModelProvider.notifier)
            .clearDownloadProgress();
      }
    });
    final choice = preference.asData?.value;
    if (choice == SyncPreference.undecided) _asking = true;
    if (choice == SyncPreference.enabled || choice == SyncPreference.disabled) {
      _asking = false;
    }
    return _asking ? widget.accountPage : widget.library;
  }
}
