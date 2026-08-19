import Foundation

/// One agent skill: a directory under the agent's `skills/` folder that
/// contains a `SKILL.md` with YAML frontmatter (`name`, `description`).
struct Skill: Identifiable, Hashable, Sendable {
    /// Folder name directly under `skills/`.
    var directoryName: String
    /// Display name from the frontmatter, falling back to `directoryName`.
    var name: String
    /// The frontmatter `description`, or empty when absent.
    var summary: String
    var directoryURL: URL

    var id: String { directoryURL.path }

    var skillFileURL: URL {
        directoryURL.appending(path: "SKILL.md")
    }
}
