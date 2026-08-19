import Foundation

/// Copies a config file into the app's Application Support folder right
/// before it gets overwritten, keeping the most recent backups per agent.
struct BackupManager {
    static let maximumBackupsPerAgent = 10

    static func backupsDirectory(for agent: AgentKind) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appending(path: "XCAgentHub/Backups")
            .appending(path: agent.rawValue)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Backs up `fileURL` if it exists and returns the backup location.
    @discardableResult
    static func backUpIfNeeded(fileURL: URL, agent: AgentKind) throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let directory = try backupsDirectory(for: agent)
        let timestamp = Date.now.ISO8601Format(.iso8601(timeZone: .current))
            .replacingOccurrences(of: ":", with: "-")
        let destination = directory.appending(path: "\(timestamp) \(fileURL.lastPathComponent)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: fileURL, to: destination)
        try prune(directory: directory)
        return destination
    }

    /// Removes the oldest backups beyond `maximumBackupsPerAgent`.
    private static func prune(directory: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        // Timestamped names sort chronologically, so the oldest come first.
        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let excess = sorted.count - maximumBackupsPerAgent
        guard excess > 0 else { return }
        for url in sorted.prefix(excess) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
