import Foundation

final class FolderInventoryReader {
  private let fileManager = FileManager.default

  func scan(root: URL) throws -> [[String: Any]] {
    let keys: [URLResourceKey] = [
      .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
      .ubiquitousItemDownloadingStatusKey, .fileSizeKey, .contentModificationDateKey,
    ]
    var entries: [[String: Any]] = []
    var enumerationError: Error?
    var coordinationError: NSError?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(
      readingItemAt: root,
      options: [.immediatelyAvailableMetadataOnly],
      error: &coordinationError
    ) { coordinatedRoot in
      guard let enumerator = self.fileManager.enumerator(
        at: coordinatedRoot,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, error in
          enumerationError = error
          return false
        }
      ) else {
        enumerationError = FolderAccessError.transientIo
        return
      }
      for case let url as URL in enumerator {
        do {
          let values = try url.resourceValues(forKeys: Set(keys))
          if values.isSymbolicLink == true {
            enumerator.skipDescendants()
            continue
          }
          guard values.isRegularFile == true else { continue }
          let ext = url.pathExtension.lowercased()
          guard ["m4a", "mp3", "srt"].contains(ext) else { continue }
          let relativePath = String(url.path.dropFirst(coordinatedRoot.path.count + 1))
          guard !relativePath.isEmpty, !relativePath.hasPrefix("../") else { continue }
          let status: String
          if values.isUbiquitousItem == true,
             values.ubiquitousItemDownloadingStatus == .notDownloaded {
            status = "pendingDownload"
          } else {
            status = "available"
          }
          entries.append([
            "relativePath": relativePath,
            "status": status,
            "byteLength": (values.fileSize as Any?) ?? NSNull(),
            "modifiedAtMs": (values.contentModificationDate.map {
              Int64($0.timeIntervalSince1970 * 1000)
            } as Any?) ?? NSNull(),
          ])
        } catch {
          // Do not return a partial inventory that could look like a source deletion.
          enumerationError = error
          continue
        }
      }
    }
    if let coordinationError {
      throw mapFileError(coordinationError)
    }
    if let enumerationError {
      throw mapFileError(enumerationError)
    }
    return entries.sorted {
      ($0["relativePath"] as? String ?? "") < ($1["relativePath"] as? String ?? "")
    }
  }

  func stageFile(root: URL, relativePath: String) throws -> URL {
    let components = relativePath.split(separator: "/")
    guard !components.isEmpty,
          components.allSatisfy({ $0 != "." && $0 != ".." }),
          !relativePath.hasPrefix("/") else {
      throw FolderAccessError.permissionDenied
    }
    let source = components.reduce(root) { $0.appendingPathComponent(String($1)) }
    let rootPath = root.standardizedFileURL.path
    let sourcePath = source.standardizedFileURL.path
    guard sourcePath.hasPrefix(rootPath + "/") else { throw FolderAccessError.permissionDenied }

    var current = root
    for component in components {
      current.appendPathComponent(String(component))
      let pathValues = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
      guard pathValues.isSymbolicLink != true else {
        throw FolderAccessError.permissionDenied
      }
    }

    let values = try source.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey,
      .ubiquitousItemDownloadingStatusKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw FolderAccessError.notFound
    }
    if values.isUbiquitousItem == true,
       values.ubiquitousItemDownloadingStatus == .notDownloaded {
      throw FolderAccessError.fileNotDownloaded
    }

    let appSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let staging = appSupport.appendingPathComponent("EnglishLearningPlayer/StagedImports", isDirectory: true)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    let destination = staging.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
    var coordinationError: NSError?
    var copyError: Error?
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: source,
      options: [],
      error: &coordinationError
    ) { coordinatedSource in
      do {
        try self.fileManager.copyItem(at: coordinatedSource, to: destination)
      } catch {
        copyError = error
      }
    }
    if let copyError {
      try? fileManager.removeItem(at: destination)
      throw mapFileError(copyError)
    }
    if let coordinationError {
      try? fileManager.removeItem(at: destination)
      throw mapFileError(coordinationError)
    }
    return destination
  }

  private func mapFileError(_ error: Error) -> FolderAccessError {
    let nsError = error as NSError
    if nsError.code == NSFileReadNoPermissionError || nsError.code == Int(EPERM) {
      return .permissionDenied
    }
    if nsError.code == NSFileNoSuchFileError || nsError.code == Int(ENOENT) {
      return .notFound
    }
    return .transientIo
  }
}

enum FolderAccessError: Error {
  case permissionDenied
  case providerUnavailable
  case fileNotDownloaded
  case notFound
  case transientIo

}
