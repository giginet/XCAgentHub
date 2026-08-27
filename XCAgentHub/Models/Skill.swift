import Foundation

/// How a skill's folder came to sit under `skills/`.
enum SkillOrigin: Hashable, Sendable {
    /// A real directory, holding its own copy of the files.
    case folder
    /// A symlink to a folder elsewhere on disk. `isReadable` is false when
    /// this app cannot follow the link — the target moved, or the sandbox
    /// grant for it was lost — in which case the skill's own frontmatter is
    /// out of reach even though the agent may still be able to use it.
    case link(destination: URL, isReadable: Bool)
}

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
    var origin: SkillOrigin = .folder

    var id: String { directoryURL.path }

    var skillFileURL: URL {
        directoryURL.appending(path: "SKILL.md")
    }

    /// The folder this skill links to, or nil when it is a real directory.
    var linkDestination: URL? {
        guard case .link(let destination, _) = origin else { return nil }
        return destination
    }

    /// A link this app cannot follow. Its row is shown so the user can remove
    /// it, but there is nothing to read or edit.
    var isBrokenLink: Bool {
        guard case .link(_, let isReadable) = origin else { return false }
        return !isReadable
    }
}
