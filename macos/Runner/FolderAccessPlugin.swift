import Cocoa
import FlutterMacOS
import CoreServices

final class FolderAccessPlugin: NSObject, FlutterStreamHandler {
  private let methodChannel = "english_learning_player/folder_access/methods"
  private let eventChannel = "english_learning_player/folder_access/events"
  private let bookmarkPrefix = "folderAccess.bookmark."
  private let fileManager = FileManager.default

  private var eventSink: FlutterEventSink?
  private var watchedBindingId: String?
  private var watchedURL: URL?
  private var eventStream: FSEventStreamRef?

  func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: methodChannel, binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else { return result(FlutterError(code: "providerUnavailable", message: nil, details: nil)) }
        self.handle(call, result: result)
      }
    FlutterEventChannel(name: eventChannel, binaryMessenger: messenger)
      .setStreamHandler(self)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let bindingId = arguments["bindingId"] as? String
    guard let bindingId, !bindingId.isEmpty else {
      result(FlutterError(code: "notFound", message: "Missing binding ID", details: nil))
      return
    }

    switch call.method {
    case "pickFolder":
      pickFolder(bindingId: bindingId, result: result)
    case "restoreGrant":
      DispatchQueue.global(qos: .utility).async {
        do {
          let status = try self.withResolvedGrant(bindingId: bindingId) { _, stale in
            stale ? "stale" : "valid"
          }
          DispatchQueue.main.async { result(status) }
        } catch let failure as FolderAccessError {
          DispatchQueue.main.async { result(failure.flutterError) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "transientIo", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "scan":
      DispatchQueue.global(qos: .utility).async {
        do {
          let entries = try self.withResolvedGrant(bindingId: bindingId) { root, _ in
            try self.scan(root: root)
          }
          DispatchQueue.main.async { result(entries) }
        } catch let failure as FolderAccessError {
          DispatchQueue.main.async { result(failure.flutterError) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "transientIo", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "stageFile":
      guard let relativePath = arguments["relativePath"] as? String else {
        result(FlutterError(code: "notFound", message: "Missing relative path", details: nil))
        return
      }
      DispatchQueue.global(qos: .utility).async {
        do {
          let staged = try self.withResolvedGrant(bindingId: bindingId) { root, _ in
            try self.stageFile(root: root, relativePath: relativePath)
          }
          DispatchQueue.main.async { result(staged.absoluteString) }
        } catch let failure as FolderAccessError {
          DispatchQueue.main.async { result(failure.flutterError) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "transientIo", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "disconnect":
      if watchedBindingId == bindingId { stopWatching() }
      UserDefaults.standard.removeObject(forKey: bookmarkKey(bindingId))
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pickFolder(bindingId: String, result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = "授權唯讀"
    panel.message = "選擇要監看的教材資料夾。原始檔案只會讀取。"

    guard panel.runModal() == .OK, let url = panel.url else {
      result(nil)
      return
    }

    do {
      let bookmark = try url.bookmarkData(
        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(bookmark, forKey: bookmarkKey(bindingId))
      result(["bindingId": bindingId, "displayLabel": url.lastPathComponent])
    } catch {
      result(FlutterError(code: "permissionDenied", message: error.localizedDescription, details: nil))
    }
  }

  private func withResolvedGrant<T>(
    bindingId: String,
    body: (URL, Bool) throws -> T
  ) throws -> T {
    guard let data = UserDefaults.standard.data(forKey: bookmarkKey(bindingId)) else {
      throw FolderAccessError.notFound
    }
    var stale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
    } catch {
      throw FolderAccessError.permissionDenied
    }
    guard url.startAccessingSecurityScopedResource() else {
      throw FolderAccessError.permissionDenied
    }
    defer { url.stopAccessingSecurityScopedResource() }

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw FolderAccessError.notFound
    }
    if stale {
      do {
        let renewed = try url.bookmarkData(
          options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        UserDefaults.standard.set(renewed, forKey: bookmarkKey(bindingId))
      } catch {
        throw FolderAccessError.permissionDenied
      }
    }
    return try body(url, stale)
  }

  private func scan(root: URL) throws -> [[String: Any]] {
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
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
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

  private func stageFile(root: URL, relativePath: String) throws -> URL {
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

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard let args = arguments as? [String: Any],
          let bindingId = args["bindingId"] as? String else {
      return FlutterError(code: "notFound", message: "Missing binding ID", details: nil)
    }
    do {
      let root = try withResolvedGrant(bindingId: bindingId) { url, _ in url }
      guard root.startAccessingSecurityScopedResource() else {
        return FolderAccessError.permissionDenied.flutterError
      }
      var context = FSEventStreamContext(
        version: 0,
        info: Unmanaged.passUnretained(self).toOpaque(),
        retain: nil,
        release: nil,
        copyDescription: nil
      )
      let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
      guard let stream = FSEventStreamCreate(
        kCFAllocatorDefault,
        Self.fileSystemEventCallback,
        &context,
        [root.path] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.75,
        flags
      ) else {
        root.stopAccessingSecurityScopedResource()
        return FlutterError(code: "providerUnavailable", message: "Cannot start file watcher", details: nil)
      }
      eventSink = events
      watchedBindingId = bindingId
      watchedURL = root
      eventStream = stream
      FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
      guard FSEventStreamStart(stream) else {
        stopWatching()
        return FlutterError(code: "providerUnavailable", message: "Cannot start file watcher", details: nil)
      }
      return nil
    } catch let failure as FolderAccessError {
      return failure.flutterError
    } catch {
      return FlutterError(code: "transientIo", message: error.localizedDescription, details: nil)
    }
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopWatching()
    return nil
  }

  private func stopWatching() {
    if let stream = eventStream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
    watchedURL?.stopAccessingSecurityScopedResource()
    eventStream = nil
    watchedURL = nil
    watchedBindingId = nil
    eventSink = nil
  }

  private func bookmarkKey(_ bindingId: String) -> String { bookmarkPrefix + bindingId }

  private static let fileSystemEventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    let plugin = Unmanaged<FolderAccessPlugin>.fromOpaque(info).takeUnretainedValue()
    DispatchQueue.main.async { plugin.eventSink?(["changed": true]) }
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

private enum FolderAccessError: Error {
  case permissionDenied
  case providerUnavailable
  case fileNotDownloaded
  case notFound
  case transientIo

  var flutterError: FlutterError {
    let code: String
    switch self {
    case .permissionDenied: code = "permissionDenied"
    case .providerUnavailable: code = "providerUnavailable"
    case .fileNotDownloaded: code = "fileNotDownloaded"
    case .notFound: code = "notFound"
    case .transientIo: code = "transientIo"
    }
    return FlutterError(code: code, message: nil, details: nil)
  }
}
