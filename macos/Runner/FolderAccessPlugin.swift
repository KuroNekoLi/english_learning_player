import Cocoa
import FlutterMacOS

final class FolderAccessPlugin: NSObject, FlutterStreamHandler {
  private let methodChannel = "english_learning_player/folder_access/methods"
  private let eventChannel = "english_learning_player/folder_access/events"
  private let bookmarks = FolderBookmarkStore()
  private let inventory = FolderInventoryReader()
  private lazy var watcher = FolderWatcher(bookmarks: bookmarks)

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
          let status = try self.bookmarks.withResolvedGrant(bindingId: bindingId) { _, stale in
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
          let entries = try self.bookmarks.withResolvedGrant(bindingId: bindingId) { root, _ in
            try self.inventory.scan(root: root)
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
          let staged = try self.bookmarks.withResolvedGrant(bindingId: bindingId) { root, _ in
            try self.inventory.stageFile(root: root, relativePath: relativePath)
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
      if watcher.watchedBindingId == bindingId { watcher.stopWatching() }
      bookmarks.remove(bindingId: bindingId)
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
      try bookmarks.save(url: url, bindingId: bindingId)
      result(["bindingId": bindingId, "displayLabel": url.lastPathComponent])
    } catch {
      result(FlutterError(code: "permissionDenied", message: error.localizedDescription, details: nil))
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard let args = arguments as? [String: Any],
          let bindingId = args["bindingId"] as? String else {
      return FlutterError(code: "notFound", message: "Missing binding ID", details: nil)
    }
    watcher.start(bindingId: bindingId) { result in
      switch result {
      case .success: events(["changed": true])
      case .failure(let error): events(error.flutterError)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    watcher.stopWatching()
    return nil
  }
}

private extension FolderAccessError {
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
