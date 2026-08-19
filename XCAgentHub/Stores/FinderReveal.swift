import AppKit
import Foundation

/// Hands a config file or skills folder to Finder.
enum FinderReveal {
    /// Opens a folder, or selects a file inside its enclosing folder. When
    /// the agent has not created the item yet, the closest folder that does
    /// exist is opened instead.
    static func show(_ url: URL) {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            return
        }
        var folder = url.deletingLastPathComponent()
        while !manager.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder = folder.deletingLastPathComponent()
        }
        NSWorkspace.shared.open(folder)
    }
}
