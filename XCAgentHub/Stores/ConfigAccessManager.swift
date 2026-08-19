import AppKit
import Foundation
import Observation

/// Manages sandboxed access to `~/Library/Developer/Xcode/CodingAssistant`.
/// The user grants access once via an open panel; the grant is persisted as
/// a security-scoped bookmark and restored on later launches.
@Observable
final class ConfigAccessManager {
    private static let bookmarkDefaultsKey = "CodingAssistantFolderBookmark"

    private(set) var rootDirectoryURL: URL?

    init() {
        restoreFromBookmark()
    }

    /// The real (non-container) location of Xcode's CodingAssistant folder,
    /// used as the open panel's starting directory. The sandboxed home APIs
    /// return the app container, so the home directory comes from passwd.
    static var defaultFolderURL: URL {
        let home: String
        if let passwd = getpwuid(getuid()), let dir = passwd.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(filePath: home).appending(path: "Library/Developer/Xcode/CodingAssistant")
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
        panel.message = "Select the CodingAssistant folder so XCAgentHub can read and update agent configurations."
        panel.prompt = "Grant Access"
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
