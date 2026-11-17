import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform/folder_access_gateway.dart';
import '../../subtitles/domain/subtitle_filename_matcher.dart';
import '../../subtitles/domain/subtitle_models.dart';
import '../../subtitles/services/subtitle_import_service.dart';
import '../domain/audio_import_source.dart';
import '../material_repository.dart';
import 'audio_import_service.dart';

final class FolderImportReconciler {
  FolderImportReconciler({
    required FolderAccessGateway gateway,
    required FolderReconciliationRepository repository,
    required MaterialRepository materials,
    required AudioImportService audioImporter,
    required SubtitleImportService subtitleImporter,
    required this.ownerId,
    this.bindingId = 'primary-icloud-source',
    this.playlistTitle = 'iCloud 資料夾',
  }) : _gateway = gateway,
       _repository = repository,
       _materials = materials,
       _audioImporter = audioImporter,
       _subtitleImporter = subtitleImporter;

  final FolderAccessGateway _gateway;
  final FolderReconciliationRepository _repository;
  final MaterialRepository _materials;
  final AudioImportService _audioImporter;
  final SubtitleImportService _subtitleImporter;
  final String ownerId;
  final String bindingId;
  final String playlistTitle;
  final SubtitleFilenameMatcher _matcher = const SubtitleFilenameMatcher();

  Future<FolderReconciliationResult> reconcile() async =>
      reconcileInventory(await _gateway.scan(bindingId));

  Future<FolderReconciliationResult> reconcileInventory(
    List<FolderEntry> inventory,
  ) async {
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
        }
        if (material == null && oldAtPath == null) {
          final renameCandidates = missingPrevious
              .where((record) => record.contentSha256 == contentHash)
              .toList();
          if (renameCandidates.length == 1 &&
              !assignedMaterials.contains(renameCandidates.single.materialId)) {
            material = knownMaterials[renameCandidates.single.materialId];
            if (material != null) renamed++;
          }
        }
        if (material == null) {
          final result = await _audioImporter.importAudio(
            AudioImportSource(
              sourceKey: _sourceKey(entry.relativePath),
              name: p.basename(entry.relativePath),
              openRead: file.openRead,
            ),
          );
          material = result.material;
          knownMaterials[material.id] = material;
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
      } catch (_) {
        failures++;
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
