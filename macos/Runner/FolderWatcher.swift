import Foundation
import CoreServices

final class FolderWatcher {
  private let bookmarks: FolderBookmarkStore
  private var onChange: ((Result<Void, FolderAccessError>) -> Void)?
  private(set) var watchedBindingId: String?
  private var watchedURL: URL?
  private var eventStream: FSEventStreamRef?
  private var watchRequest: UUID?

  init(bookmarks: FolderBookmarkStore) {
    self.bookmarks = bookmarks
  }

  deinit { stopWatching() }

  func start(bindingId: String, onEvent: @escaping (Result<Void, FolderAccessError>) -> Void) {
    stopWatching()
    let request = UUID()
    watchRequest = request
    watchedBindingId = bindingId
    onChange = onEvent
    DispatchQueue.global(qos: .utility).async {
      do {
        let root = try self.bookmarks.withResolvedGrant(bindingId: bindingId) { url, _ in url }
        guard root.startAccessingSecurityScopedResource() else {
          throw FolderAccessError.permissionDenied
        }
        var context = FSEventStreamContext(
          version: 0,
          info: Unmanaged.passUnretained(self).toOpaque(),
          retain: nil,
          release: nil,
          copyDescription: nil
        )
        // WatchRoot opens parent directories, which can block for provider-backed folders.
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
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
          throw FolderAccessError.providerUnavailable
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
          FSEventStreamInvalidate(stream)
          FSEventStreamRelease(stream)
          root.stopAccessingSecurityScopedResource()
          throw FolderAccessError.providerUnavailable
        }
        DispatchQueue.main.async {
          guard self.watchRequest == request else {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            root.stopAccessingSecurityScopedResource()
            return
          }
          self.watchedURL = root
          self.eventStream = stream
          // Close the gap between the initial inventory and attaching the watcher.
          self.onChange?(.success(()))
        }
      } catch {
        DispatchQueue.main.async {
          guard self.watchRequest == request else { return }
          self.onChange?(.failure(error as? FolderAccessError ?? .transientIo))
          self.stopWatching()
        }
      }
    }
  }

  func stopWatching() {
    watchRequest = nil
    if let stream = eventStream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
    watchedURL?.stopAccessingSecurityScopedResource()
    eventStream = nil
    watchedURL = nil
    watchedBindingId = nil
    onChange = nil
  }

  private static let fileSystemEventCallback: FSEventStreamCallback = { stream, info, _, _, _, _ in
    guard let info else { return }
    let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
    if watcher.eventStream == stream { watcher.onChange?(.success(())) }
  }

}
