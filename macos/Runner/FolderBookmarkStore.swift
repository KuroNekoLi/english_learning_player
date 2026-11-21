import Foundation

final class FolderBookmarkStore {
  private let fileManager = FileManager.default
  private let bookmarkPrefix = "folderAccess.bookmark."

  func save(url: URL, bindingId: String) throws {
    let bookmark = try url.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    UserDefaults.standard.set(bookmark, forKey: bookmarkKey(bindingId))
  }

  func remove(bindingId: String) {
    UserDefaults.standard.removeObject(forKey: bookmarkKey(bindingId))
  }

  func withResolvedGrant<T>(
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
        options: [.withSecurityScope, .withoutUI, .withoutMounting],
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

  private func bookmarkKey(_ bindingId: String) -> String { bookmarkPrefix + bindingId }

}
