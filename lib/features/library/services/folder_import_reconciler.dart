import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform/folder_access_gateway.dart';
import '../../subtitles/domain/subtitle_filename_matcher.dart';
import '../../subtitles/domain/subtitle_models.dart';
import '../../subtitles/services/subtitle_import_service.dart';
import '../domain/audio_import_source.dart';
import '../library_folder_repository.dart';
import '../material_repository.dart';
import 'audio_import_service.dart';
import 'media_selection_import_service.dart';

typedef FolderImportProgressCallback = void Function(
  List<MediaFileImportProgress> progress,
);

final class FolderImportReconciler {
  FolderImportReconciler({
    required this._gateway,
    required this._repository,
    required this._materials,
    required this._audioImporter,
    required this._subtitleImporter,
    required this.ownerId,
    this.libraryFolders,
    this.bindingId = 'primary-icloud-source',
    this.playlistTitle = 'iCloud 資料夾',
  });

  final FolderAccessGateway _gateway;
  final FolderReconciliationRepository _repository;
  final MaterialRepository _materials;
  final AudioImportService _audioImporter;
  final SubtitleImportService _subtitleImporter;
  final String ownerId;
  final LibraryFolderRepository? libraryFolders;
  final String bindingId;
  final String playlistTitle;
  final SubtitleFilenameMatcher _matcher = const SubtitleFilenameMatcher();

  Future<FolderReconciliationResult> reconcile() async =>
      reconcileInventory(await _gateway.scan(bindingId));

  Future<FolderReconciliationResult> reconcileInventory(
    List<FolderEntry> inventory, {
    String? sourceFolderName,
    FolderImportProgressCallback? onProgress,
  }) async {
    // A failed scan cannot imply source deletion. Mark absent only after a
    // complete inventory has been returned successfully.
    final previous = await _repository.listFolderSources(bindingId);
    final knownMaterials = {
      for (final material in await _materials.listMaterials())
        material.id: material,
    };
    final previousByPath = {
      for (final record in previous) record.relativePath: record,
    };
    final audioEntries = inventory
        .where((entry) => _isAudio(entry.relativePath))
        .toList();
    final subtitleEntries = inventory
        .where((entry) => _isSubtitle(entry.relativePath))
        .toList();
    final folderIds = await _ensureImportedFolders(
      inventory,
      sourceFolderName: sourceFolderName,
    );
    final currentAudioPaths = audioEntries
        .map((entry) => entry.relativePath)
        .toSet();
    final missingPrevious = previous
        .where(
          (record) =>
              record.present &&
              !currentAudioPaths.contains(record.relativePath),
        )
        .toList();

    final assignedMaterials = {
      for (final record in previous)
        if (currentAudioPaths.contains(record.relativePath)) record.materialId,
    };
    var imported = 0;
    var renamed = 0;
    var duplicates = 0;
    var pending = 0;
    var failures = 0;
    final materialByAudioPath = <String, LearningMaterial>{};
    final importProgress = <MediaFileImportProgress>[];
    void publishProgress() =>
        onProgress?.call(List.unmodifiable(importProgress));

    for (final entry in audioEntries) {
      final oldAtPath = previousByPath[entry.relativePath];
      if (oldAtPath != null) {
        // The inventory proves source presence even when staging/import fails.
        await _repository.saveFolderSource(
          bindingId: bindingId,
          relativePath: entry.relativePath,
          materialId: oldAtPath.materialId,
          contentSha256: oldAtPath.contentSha256,
        );
      }
      if (entry.status == FolderEntryStatus.pendingDownload) {
        pending++;
        continue;
      }
      File? stagedFile;
      try {
        final file = stagedFile = File.fromUri(
          await _gateway.stageFile(bindingId, entry.relativePath),
        );
        final digest = await sha256.bind(file.openRead()).first;
        final contentHash = digest.toString();
        LearningMaterial? material;
        if (oldAtPath != null && oldAtPath.contentSha256 == contentHash) {
          material = knownMaterials[oldAtPath.materialId];
          // Existing source rows reference a material in this account. A
          // hidden material must not be recreated by a rescan of the same bytes.
          if (material == null) continue;
        }
        if (material == null && oldAtPath == null) {
          final renameCandidates = missingPrevious
              .where((record) => record.contentSha256 == contentHash)
              .toList();
          if (renameCandidates.length == 1 &&
              !assignedMaterials.contains(renameCandidates.single.materialId)) {
            final previous = renameCandidates.single;
            material = knownMaterials[previous.materialId];
            if (material == null) {
              await _repository.saveFolderSource(
                bindingId: bindingId,
                relativePath: entry.relativePath,
                materialId: previous.materialId,
                contentSha256: contentHash,
              );
              assignedMaterials.add(previous.materialId);
              continue;
            }
            renamed++;
          }
        }
        if (material == null) {
          final progressIndex = importProgress.length;
          importProgress.add(
            MediaFileImportProgress(
              sourceName: entry.relativePath,
              status: MediaFileImportStatus.importing,
            ),
          );
          publishProgress();
          final result = await _audioImporter.importAudio(
            AudioImportSource(
              sourceKey: _sourceKey(entry.relativePath),
              name: p.basename(entry.relativePath),
              byteLength: entry.byteLength,
              openRead: file.openRead,
            ),
            onProgress: (bytesCopied, totalBytes) {
              importProgress[progressIndex] = importProgress[progressIndex]
                  .copyWith(
                    bytesCopied: bytesCopied,
                    totalBytes: totalBytes,
                    status: MediaFileImportStatus.importing,
                  );
              publishProgress();
            },
          );
          material = result.material;
          knownMaterials[material.id] = material;
          importProgress[progressIndex] = importProgress[progressIndex]
              .copyWith(status: MediaFileImportStatus.completed);
          publishProgress();
          if (result.wasDuplicate) {
            duplicates++;
          } else {
            imported++;
          }
        }
        assignedMaterials.add(material.id);
        materialByAudioPath[entry.relativePath] = material;
        await _repository.saveFolderSource(
          bindingId: bindingId,
          relativePath: entry.relativePath,
          materialId: material.id,
          contentSha256: contentHash,
        );
        await _repository.addToFolderPlaylist(
          bindingId: bindingId,
          materialId: material.id,
          title: playlistTitle,
        );
        final directory = p.posix.dirname(entry.relativePath);
        final folderId = folderIds[directory == '.' ? '' : directory];
        if (folderId != null) {
          await libraryFolders?.addMaterial(folderId, material.id);
        }
      } catch (_) {
        failures++;
        if (importProgress.isNotEmpty &&
            importProgress.last.sourceName == entry.relativePath &&
            importProgress.last.status != MediaFileImportStatus.completed) {
          importProgress[importProgress.length - 1] = importProgress.last
              .copyWith(status: MediaFileImportStatus.failed);
          publishProgress();
        }
      } finally {
        await _deleteStaging(stagedFile);
      }
    }

    var subtitlesImported = 0;
    var ambiguousSubtitles = 0;
    for (final audioEntry in audioEntries) {
      final material = materialByAudioPath[audioEntry.relativePath];
      if (material == null) continue;
      final tracks = await _materials.listSubtitleTracks(material.id);
      final manualSelections = <SubtitleLanguage, String>{};
      for (final track in tracks) {
        if (track.selectionMode != SubtitleSelectionMode.manual ||
            !track.isSelected) {
          continue;
        }
        final language = _language(track.languageTag);
        if (language != null) manualSelections[language] = track.sourceName;
      }
      final nearbySubtitles = subtitleEntries.where(
        (entry) =>
            p.dirname(entry.relativePath) == p.dirname(audioEntry.relativePath),
      );
      final matches = _matcher.match(
        audioFileName: audioEntry.relativePath,
        subtitleFileNames: nearbySubtitles.map((entry) => entry.relativePath),
        manualSelections: manualSelections,
      );
      for (final language in SubtitleLanguage.values) {
        final match = matches[language]!;
        if (match.status == SubtitleMatchStatus.ambiguous) {
          ambiguousSubtitles++;
          continue;
        }
        final sourceName = match.selectedSourceName;
        if (sourceName == null ||
            (match.status == SubtitleMatchStatus.manual &&
                !nearbySubtitles.any(
                  (entry) => p.basename(entry.relativePath) == sourceName,
                ))) {
          continue;
        }
        final subtitleEntry = nearbySubtitles
            .where((entry) => p.basename(entry.relativePath) == sourceName)
            .firstOrNull;
        if (subtitleEntry == null ||
            subtitleEntry.status != FolderEntryStatus.available) {
          if (subtitleEntry?.status == FolderEntryStatus.pendingDownload) {
            pending++;
          }
          continue;
        }
        File? stagedFile;
        try {
          final staged = await _gateway.stageFile(
            bindingId,
            subtitleEntry.relativePath,
          );
          final file = stagedFile = File.fromUri(staged);
          final bytes = await file.readAsBytes();
          final languageTag = language == SubtitleLanguage.english
              ? 'en'
              : 'zh-TW';
          final identical = tracks.any(
            (track) =>
                track.sourceName == p.basename(subtitleEntry.relativePath) &&
                _sameBytes(track.originalBytes, bytes),
          );
          if (identical) continue;
          await _subtitleImporter.importBytes(
            ownerId: ownerId,
            materialId: material.id,
            languageTag: languageTag,
            sourceName: subtitleEntry.relativePath,
            bytes: bytes,
            manual: false,
          );
          subtitlesImported++;
        } catch (_) {
          failures++;
        } finally {
          await _deleteStaging(stagedFile);
        }
      }
    }

    await _repository.finishFolderScan(
      bindingId: bindingId,
      inventoryPaths: inventory.map((entry) => entry.relativePath).toSet(),
    );

    return FolderReconciliationResult(
      importedAudio: imported,
      renamedAudio: renamed,
      duplicateAudio: duplicates,
      importedSubtitles: subtitlesImported,
      pendingDownload: pending,
      ambiguousSubtitles: ambiguousSubtitles,
      failures: failures,
      missingSourceEntries: previous
          .where(
            (record) =>
                record.present &&
                !currentAudioPaths.contains(record.relativePath),
          )
          .length,
    );
  }

  Future<Map<String, String>> _ensureImportedFolders(
    List<FolderEntry> inventory, {
    String? sourceFolderName,
  }) async {
    final repository = libraryFolders;
    if (repository == null) return const {};

    final directories = <String>{''};
    for (final entry in inventory) {
      var directory = p.posix.dirname(entry.relativePath);
      while (directory != '.' && directory.isNotEmpty) {
        directories.add(directory);
        directory = p.posix.dirname(directory);
      }
    }
    final ordered = directories.toList()
      ..sort((left, right) {
        final depthOrder = left
            .split('/')
            .length
            .compareTo(right.split('/').length);
        return depthOrder != 0 ? depthOrder : left.compareTo(right);
      });
    final existingFolders = {
      for (final folder in await repository.listFolders()) folder.id: folder,
    };
    final ids = <String, String>{};
    for (final directory in ordered) {
      final isRoot = directory.isEmpty;
      final parentPath = isRoot ? null : p.posix.dirname(directory);
      final parentId = parentPath == null || parentPath == '.'
          ? null
          : ids[parentPath];
      final id = _importedFolderId(directory);
      final existing = existingFolders[id];
      final title = isRoot
          ? (sourceFolderName?.trim().isNotEmpty == true
                ? sourceFolderName!.trim()
                : existing?.title ?? playlistTitle)
          : p.posix.basename(directory);
      if (existing == null ||
          existing.title != title ||
          existing.parentId != parentId) {
        await repository.createFolder(title, id: id, parentId: parentId);
      }
      ids[directory] = id;
    }
    return ids;
  }

  String _importedFolderId(String relativeDirectory) =>
      'import-${sha256.convert(utf8.encode('$bindingId\u0000$relativeDirectory')).toString().substring(0, 32)}';

  Future<void> _deleteStaging(File? file) async {
    try {
      await file?.delete();
    } on FileSystemException {
      // Staging cleanup must not undo a committed import.
    }
  }

  String _sourceKey(String relativePath) =>
      sha256.convert(utf8.encode('$bindingId\u0000$relativePath')).toString();

  SubtitleLanguage? _language(String tag) {
    final lower = tag.toLowerCase();
    if (lower.startsWith('en')) return SubtitleLanguage.english;
    if (lower.startsWith('zh')) return SubtitleLanguage.chinese;
    return null;
  }

  bool _isAudio(String path) =>
      const {'.m4a', '.mp3'}.contains(p.extension(path).toLowerCase());
  bool _isSubtitle(String path) => p.extension(path).toLowerCase() == '.srt';
  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

final class FolderReconciliationResult {
  const FolderReconciliationResult({
    required this.importedAudio,
    required this.renamedAudio,
    required this.duplicateAudio,
    required this.importedSubtitles,
    required this.pendingDownload,
    required this.ambiguousSubtitles,
    required this.failures,
    required this.missingSourceEntries,
  });

  final int importedAudio;
  final int renamedAudio;
  final int duplicateAudio;
  final int importedSubtitles;
  final int pendingDownload;
  final int ambiguousSubtitles;
  final int failures;
  final int missingSourceEntries;
}
