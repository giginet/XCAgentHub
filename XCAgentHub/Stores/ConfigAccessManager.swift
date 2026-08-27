import AppKit
import Foundation
import Observation

/// Manages sandboxed access to `~/Library/Developer/Xcode/CodingAssistant`.
/// The user grants access once via an open panel; the grant is persisted as
/// a security-scoped bookmark and restored on later launches.
@Observable
final class ConfigAccessManager {
    private static let bookmarkDefaultsKey = "CodingAssistantFolderBookmark"
    private static let linkBookmarksDefaultsKey = "LinkedSkillFolderBookmarks"

    private(set) var rootDirectoryURL: URL?

    /// Security-scoped bookmarks for folders linked into an agent's skills
    /// directory, keyed by the path of the symlink pointing at them. A link
    /// leaves the granted root behind, so without one of these the app loses
    /// sight of the skill the moment it relaunches.
    private var linkBookmarks: [String: Data] = [:]

    init() {
        restoreFromBookmark()
        restoreLinkBookmarks()
    }

    /// The user's real home directory. The sandboxed home APIs return the app
    /// container, so it comes from passwd instead.
    static var realHomeURL: URL {
        let home: String
        if let passwd = getpwuid(getuid()), let dir = passwd.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(filePath: home)
    }

    /// The real (non-container) location of Xcode's CodingAssistant folder,
    /// used as the open panel's starting directory.
    static var defaultFolderURL: URL {
        realHomeURL.appending(path: "Library/Developer/Xcode/CodingAssistant")
    }

    /// A path with the real home folder shown as `~`, for display. Paths to
    /// linked folders are long and the interesting part is the tail.
    static func abbreviatingHome(_ path: String) -> String {
        let home = realHomeURL.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private func restoreFromBookmark() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkDefaultsKey) else { return }
        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ),
            url.startAccessingSecurityScopedResource()
        else {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkDefaultsKey)
            return
        }
        if isStale, let refreshed = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(refreshed, forKey: Self.bookmarkDefaultsKey)
        }
        rootDirectoryURL = url
    }

    // MARK: - Linked skill folders

    /// Bookmarks a folder about to be linked into a skills directory. Call it
    /// while the open panel's grant is still live — that is the only moment
    /// the folder is reachable — and before creating the link, so a failure
    /// here leaves nothing behind on disk.
    func makeLinkBookmark(for target: URL) throws -> Data {
        try target.bookmarkData(options: .withSecurityScope)
    }

    func rememberLink(at linkURL: URL, bookmark: Data) {
        linkBookmarks[linkURL.standardizedFileURL.path] = bookmark
        persistLinkBookmarks()
    }

    func forgetLink(at linkURL: URL) {
        guard linkBookmarks.removeValue(forKey: linkURL.standardizedFileURL.path) != nil else { return }
        persistLinkBookmarks()
    }

    /// Reopens every linked folder from its bookmark. Like the root grant,
    /// the scope is started and held for the lifetime of the process.
    private func restoreLinkBookmarks() {
        guard
            let stored = UserDefaults.standard.dictionary(forKey: Self.linkBookmarksDefaultsKey)
                as? [String: Data]
        else { return }

        var surviving: [String: Data] = [:]
        for (path, data) in stored {
            var isStale = false
            guard
                let url = try? URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ),
                url.startAccessingSecurityScopedResource()
            else {
                // The folder moved or the grant lapsed. Drop the bookmark; the
                // link itself stays on disk and is listed as broken, which is
                // what the user needs to see to fix it.
                continue
            }
            surviving[path] = isStale
                ? ((try? url.bookmarkData(options: .withSecurityScope)) ?? data)
                : data
        }
        linkBookmarks = surviving
        if surviving.count != stored.count {
            persistLinkBookmarks()
        }
    }

    private func persistLinkBookmarks() {
        if linkBookmarks.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.linkBookmarksDefaultsKey)
        } else {
            UserDefaults.standard.set(linkBookmarks, forKey: Self.linkBookmarksDefaultsKey)
        }
    }

    /// Presents an open panel so the user can grant access to the folder.
    /// Returns true when access was granted.
    @discardableResult
    func promptForFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = Self.defaultFolderURL
        panel.message = String(
            localized: "Select the CodingAssistant folder so AgentHub can read and update agent configurations."
        )
        panel.prompt = String(localized: "Grant Access")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkDefaultsKey)
            _ = url.startAccessingSecurityScopedResource()
            rootDirectoryURL = url
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }
}
