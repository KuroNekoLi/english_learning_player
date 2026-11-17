import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/folder_access_gateway.dart';
import '../../core/platform/folder_access_gateway_provider.dart';
import '../subtitles/services/subtitle_import_service.dart';
import 'material_repository.dart';
import 'services/folder_import_reconciler.dart';
import 'library_view_model.dart';

const macFolderBindingId = 'primary-icloud-source';

final reconcileFolderInventoryProvider =
    Provider<
      Future<FolderReconciliationResult> Function(String, List<FolderEntry>)
    >(
      (ref) => (bindingId, entries) async {
        final gateway = ref.read(folderAccessGatewayProvider);
        final scope = ref.read(accountScopeProvider);
        final materials = ref.read(materialRepositoryProvider.future);
        final importer = ref.read(audioImportServiceProvider.future);
        final repository = await materials;
        return FolderImportReconciler(
          gateway: gateway,
          repository: repository as FolderReconciliationRepository,
          materials: repository,
          audioImporter: await importer,
          subtitleImporter: SubtitleImportService(repository: repository),
          ownerId: scope.ownerId,
          bindingId: bindingId,
        ).reconcileInventory(entries);
      },
    );

final folderSourceViewModelProvider =
    NotifierProvider<FolderSourceViewModel, FolderSourceState>(
      FolderSourceViewModel.new,
    );

final class FolderSourceState {
  const FolderSourceState({
    this.grantStatus = GrantStatus.missing,
    this.displayLabel,
    this.entries = const [],
    this.isBusy = false,
    this.error,
    this.reconciliationSummary,
  });

  final GrantStatus grantStatus;
  final String? displayLabel;
  final List<FolderEntry> entries;
  final bool isBusy;
  final String? error;
  final String? reconciliationSummary;

  int get availableCount => entries
      .where((entry) => entry.status == FolderEntryStatus.available)
      .length;
  int get pendingCount => entries
      .where((entry) => entry.status == FolderEntryStatus.pendingDownload)
      .length;

  FolderSourceState copyWith({
    GrantStatus? grantStatus,
    String? displayLabel,
    List<FolderEntry>? entries,
    bool? isBusy,
    String? error,
    bool clearError = false,
    String? reconciliationSummary,
    bool clearSummary = false,
  }) => FolderSourceState(
    grantStatus: grantStatus ?? this.grantStatus,
    displayLabel: displayLabel ?? this.displayLabel,
    entries: entries ?? this.entries,
    isBusy: isBusy ?? this.isBusy,
    error: clearError ? null : error ?? this.error,
    reconciliationSummary:
        reconciliationSummary ??
        (clearSummary ? null : this.reconciliationSummary),
  );
}

final class FolderSourceViewModel extends Notifier<FolderSourceState> {
  late FolderAccessGateway _gateway;
  StreamSubscription<void>? _watchSubscription;
  Timer? _rescanTimer;
  Timer? _periodicScan;
  late String _bindingId;
  Future<void>? _refreshing;
  bool _rescanRequested = false;
  bool _disconnecting = false;

  @override
  FolderSourceState build() {
    _gateway = ref.watch(folderAccessGatewayProvider);
    final scope = ref.watch(accountScopeProvider);
    _bindingId = scope.ownerId == 'local-default'
        ? macFolderBindingId
        : '$macFolderBindingId-${scope.storageKey}';
    ref.onDispose(() {
      _rescanTimer?.cancel();
      _periodicScan?.cancel();
      unawaited(_watchSubscription?.cancel());
    });
    unawaited(_restore());
    return const FolderSourceState(isBusy: true);
  }

  Future<void> connect() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final folder = await _gateway.pickFolder(_bindingId);
      if (folder == null) {
        state = state.copyWith(isBusy: false);
        return;
      }
      state = state.copyWith(
        grantStatus: GrantStatus.valid,
        displayLabel: folder.displayLabel,
      );
      await _startWatching();
      await refresh();
    } on FolderAccessException catch (error) {
      state = state.copyWith(isBusy: false, error: _message(error.failure));
    } catch (_) {
      state = state.copyWith(isBusy: false, error: '無法授權資料夾');
    }
  }

  Future<void> refresh() {
    if (!ref.mounted || _disconnecting) return Future.value();
    _rescanRequested = true;
    return _refreshing ??= _drainScans().whenComplete(() => _refreshing = null);
  }

  Future<void> _drainScans() async {
    while (_rescanRequested && !_disconnecting && ref.mounted) {
      _rescanRequested = false;
      state = state.copyWith(isBusy: true, clearError: true);
      await _refresh();
    }
  }

  Future<void> disconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;
    _rescanRequested = false;
    _rescanTimer?.cancel();
    _periodicScan?.cancel();
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _watchSubscription?.cancel();
      _watchSubscription = null;
      await _refreshing;
      await _gateway.disconnect(_bindingId);
      state = const FolderSourceState();
    } on FolderAccessException catch (error) {
      state = state.copyWith(isBusy: false, error: _message(error.failure));
    } catch (_) {
      state = state.copyWith(isBusy: false, error: '無法解除資料夾授權');
    } finally {
      _disconnecting = false;
    }
  }

  Future<void> _restore() async {
    try {
      final status = await _gateway.restoreGrant(_bindingId);
      if (!ref.mounted) return;
      final connected =
          status == GrantStatus.valid || status == GrantStatus.stale;
      state = state.copyWith(
        grantStatus: status,
        displayLabel: connected ? '已授權資料夾' : null,
        isBusy: connected,
      );
      if (connected) {
        await _startWatching();
        await refresh();
      }
    } on FolderAccessException catch (error) {
      final status = switch (error.failure) {
        FolderFailure.notFound => GrantStatus.missing,
        FolderFailure.permissionDenied => GrantStatus.denied,
        _ => state.grantStatus,
      };
      state = state.copyWith(
        grantStatus: status,
        isBusy: false,
        error: switch (error.failure) {
          FolderFailure.notFound => null,
          FolderFailure.permissionDenied => '資料夾授權已撤銷，請重新選取',
          FolderFailure.providerUnavailable => '此平台不支援 iCloud 資料夾授權',
          FolderFailure.fileNotDownloaded => '資料夾授權仍有效，但來源尚未完整下載',
          FolderFailure.transientIo => '資料夾授權暫時無法讀取，請稍後重試',
        },
        clearError: error.failure == FolderFailure.notFound,
      );
    } catch (_) {
      state = state.copyWith(
        grantStatus: GrantStatus.denied,
        isBusy: false,
        error: '資料夾授權無法恢復，請重新選取',
      );
    }
  }

  Future<void> _refresh() async {
    try {
      final binding = _bindingId;
      final entries = await _gateway.scan(binding);
      if (_disconnecting || !ref.mounted || binding != _bindingId) return;
      final result = await ref.read(reconcileFolderInventoryProvider)(
        binding,
        entries,
      );
      if (_disconnecting || !ref.mounted || binding != _bindingId) return;
      ref.invalidate(libraryViewModelProvider);
      state = state.copyWith(
        grantStatus: GrantStatus.valid,
        entries: entries,
        reconciliationSummary:
            result.importedAudio +
                    result.importedSubtitles +
                    result.renamedAudio +
                    result.failures +
                    result.ambiguousSubtitles >
                0
            ? '新增音訊 ${result.importedAudio}、字幕 ${result.importedSubtitles}、'
                  '改名沿用 ${result.renamedAudio}、歧義 ${result.ambiguousSubtitles}、'
                  '失敗 ${result.failures}'
            : null,
        clearSummary: true,
        isBusy: false,
        clearError: true,
      );
    } on FolderAccessException catch (error) {
      if (_disconnecting || !ref.mounted) return;
      state = state.copyWith(
        grantStatus: error.failure == FolderFailure.permissionDenied
            ? GrantStatus.denied
            : state.grantStatus,
        isBusy: false,
        error: _message(error.failure),
      );
    } catch (_) {
      if (!_disconnecting && ref.mounted) {
        state = state.copyWith(isBusy: false, error: '資料夾掃描或匯入失敗');
      }
    }
  }

  Future<void> _startWatching() async {
    await _watchSubscription?.cancel();
    if (!ref.mounted) return;
    _periodicScan?.cancel();
    _periodicScan = Timer.periodic(const Duration(minutes: 5), (_) {
      if (state.grantStatus == GrantStatus.valid) unawaited(refresh());
    });
    _watchSubscription = _gateway
        .watch(_bindingId)
        .listen(
          (_) {
            _rescanTimer?.cancel();
            _rescanTimer = Timer(const Duration(milliseconds: 350), () {
              unawaited(refresh());
            });
          },
          onError: (_) {
            state = state.copyWith(error: '資料夾監看中斷，請重新整理');
          },
        );
  }

  String _message(FolderFailure failure) => switch (failure) {
    FolderFailure.permissionDenied => '資料夾權限已撤銷，請重新選取',
    FolderFailure.providerUnavailable => '此平台不支援 iCloud 資料夾授權',
    FolderFailure.fileNotDownloaded => '檔案尚未從 iCloud 下載',
    FolderFailure.notFound => '資料夾或檔案不存在',
    FolderFailure.transientIo => '資料夾讀取失敗，請稍後重試',
  };
}
