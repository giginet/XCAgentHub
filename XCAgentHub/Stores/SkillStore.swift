import Foundation

enum SkillStoreError: LocalizedError {
    case invalidName
    case skillAlreadyExists(String)
    case notASkillDirectory(String)
    case unreadableLinkTarget(name: String, targetDirectory: String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "The skill name must contain at least one letter or number."
        case .skillAlreadyExists(let name):
            return "A skill named \u{201C}\(name)\u{201D} already exists."
        case .notASkillDirectory(let name):
            return "The folder \u{201C}\(name)\u{201D} does not contain a SKILL.md file."
        case .unreadableLinkTarget(let name, let targetDirectory):
            return "\u{201C}\(name)\u{201D} links into \(targetDirectory), which this app cannot read. Import that folder directly instead, or replace the link with a copy."
        }
    }
}

/// Manages the skills of one agent: directories under `skills/`, each with a
/// `SKILL.md` whose YAML frontmatter provides `name` and `description`.
struct SkillStore {
    let skillsDirectoryURL: URL
    let agent: AgentKind

    // MARK: - Listing

    /// All skills, sorted by name. Hidden entries (e.g. Codex's `.system`)
    /// and directories without a SKILL.md are skipped.
    func list() throws -> [Skill] {
        guard FileManager.default.fileExists(atPath: skillsDirectoryURL.path) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: skillsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        var skills: [Skill] = []
        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let skill = makeSkill(directoryURL: url)
            guard FileManager.default.fileExists(atPath: skill.skillFileURL.path) else { continue }
            skills.append(skill)
        }
        return skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Reading and writing

    func readContent(of skill: Skill) throws -> String {
        try String(contentsOf: skill.skillFileURL, encoding: .utf8)
    }

    func save(content: String, to skill: Skill) throws {
        try BackupManager.backUpIfNeeded(fileURL: skill.skillFileURL, agent: agent)
        try Data(content.utf8).write(to: skill.skillFileURL, options: .atomic)
    }

    /// Creates a new skill directory. The folder name is a sanitized form of
    /// `name`; when `content` has no frontmatter, one carrying the name is
    /// prepended so agents can discover the skill.
    @discardableResult
    func create(named name: String, content: String) throws -> Skill {
        let directoryName = Self.sanitizeDirectoryName(name)
        guard !directoryName.isEmpty else {
            throw SkillStoreError.invalidName
        }
        let directoryURL = skillsDirectoryURL.appending(path: directoryName)
        guard !FileManager.default.fileExists(atPath: directoryURL.path) else {
            throw SkillStoreError.skillAlreadyExists(directoryName)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var finalContent = content
        if !finalContent.hasPrefix("---") {
            finalContent = """
            ---
            name: \(directoryName)
            ---

            \(content)
            """
        }
        try Data(finalContent.utf8).write(
            to: directoryURL.appending(path: "SKILL.md"),
            options: .atomic
        )
        return makeSkill(directoryURL: directoryURL)
    }

    /// Copies a skill directory (must contain SKILL.md) into `skills/`,
    /// materializing symlinks along the way. `copyItem` would copy a link as
    /// a link, and skills kept in a dotfiles repo commonly symlink their
    /// SKILL.md: a relative link breaks the moment it is copied elsewhere,
    /// and an absolute one points outside the sandbox. Either way the copied
    /// skill would be unreadable and never show up in the list.
    @discardableResult
    func importSkill(from sourceDirectory: URL) throws -> Skill {
        let source = sourceDirectory.resolvingSymlinksInPath()
        let sourceSkillFile = source.appending(path: "SKILL.md")
        guard FileManager.default.fileExists(atPath: sourceSkillFile.path) else {
            // Reading the link itself is allowed even when its target is not,
            // so say which folder is out of reach rather than claiming the
            // skill has no SKILL.md.
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: sourceSkillFile.path) {
                throw SkillStoreError.unreadableLinkTarget(
                    name: "SKILL.md",
                    targetDirectory: URL(filePath: target, relativeTo: source)
                        .standardizedFileURL
                        .deletingLastPathComponent()
                        .path
                )
            }
            throw SkillStoreError.notASkillDirectory(sourceDirectory.lastPathComponent)
        }
        let destination = skillsDirectoryURL.appending(path: sourceDirectory.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw SkillStoreError.skillAlreadyExists(sourceDirectory.lastPathComponent)
        }
        try FileManager.default.createDirectory(at: skillsDirectoryURL, withIntermediateDirectories: true)
        do {
            try Self.copyResolvingSymlinks(from: source, to: destination)
        } catch {
            // Never leave a half-copied folder behind: it would make every
            // later attempt fail as "already exists".
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return makeSkill(directoryURL: destination)
    }

    /// Recursive copy that follows symlinks rather than preserving them.
    /// Entries whose target does not resolve are skipped, since they carry no
    /// content; `depth` stops a symlink loop from recursing forever.
    ///
    /// A link may also resolve to a path the app is not allowed to read: the
    /// open panel grants access to the folder the user picked, not to wherever
    /// its links point. That is reported rather than skipped, because it would
    /// otherwise produce a skill with pieces silently missing.
    private static func copyResolvingSymlinks(from source: URL, to destination: URL, depth: Int = 0) throws {
        guard depth < 16 else { return }
        let manager = FileManager.default
        let resolved = source.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else { return }
        guard resolved.path == source.path || manager.isReadableFile(atPath: resolved.path) else {
            throw SkillStoreError.unreadableLinkTarget(
                name: source.lastPathComponent,
                targetDirectory: resolved.deletingLastPathComponent().path
            )
        }
        guard isDirectory.boolValue else {
            try manager.copyItem(at: resolved, to: destination)
            return
        }
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in try manager.contentsOfDirectory(at: resolved, includingPropertiesForKeys: nil) {
            try copyResolvingSymlinks(
                from: entry,
                to: destination.appending(path: entry.lastPathComponent),
                depth: depth + 1
            )
        }
    }

    func delete(_ skill: Skill) throws {
        try FileManager.default.removeItem(at: skill.directoryURL)
    }

    // MARK: - Helpers

    private func makeSkill(directoryURL: URL) -> Skill {
        let skillFileURL = directoryURL.appending(path: "SKILL.md")
        let frontmatter = Self.parseFrontmatter(
            (try? String(contentsOf: skillFileURL, encoding: .utf8)) ?? ""
        )
        return Skill(
            directoryName: directoryURL.lastPathComponent,
            name: frontmatter["name"] ?? directoryURL.lastPathComponent,
            summary: frontmatter["description"] ?? "",
            directoryURL: directoryURL
        )
    }

    /// Minimal YAML frontmatter reader: a leading `---` line followed by
    /// `key: value` lines until the closing `---`. Multi-line values are not
    /// supported; unterminated frontmatter yields nothing.
    static func parseFrontmatter(_ content: String) -> [String: String] {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        lines = lines.dropFirst()

        var values: [String: String] = [:]
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                return values
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty {
                values[key] = value
            }
        }
        return [:]
    }

    /// Lowercases and keeps `[a-z0-9-]`, mapping spaces and underscores to
    /// single dashes: "My Cool Skill" → "my-cool-skill".
    static func sanitizeDirectoryName(_ name: String) -> String {
        var result = ""
        var lastWasDash = false
        for character in name.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber) {
                result.append(character)
                lastWasDash = false
            } else if character == "-" || character == " " || character == "_" {
                if !result.isEmpty && !lastWasDash {
                    result.append("-")
                    lastWasDash = true
                }
            }
        }
        while result.hasSuffix("-") {
            result.removeLast()
        }
        return result
    }
}
