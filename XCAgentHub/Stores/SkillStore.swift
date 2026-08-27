import Foundation

enum SkillStoreError: LocalizedError {
    case invalidName
    case skillAlreadyExists(String)
    case notASkillDirectory(String)
    case unreadableLinkTarget(name: String, targetDirectory: String)
    case cannotLinkManagedFolder(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return String(localized: "The skill name must contain at least one letter or number.")
        case .skillAlreadyExists(let name):
            return String(localized: "A skill named \u{201C}\(name)\u{201D} already exists.")
        case .notASkillDirectory(let name):
            return String(localized: "The folder \u{201C}\(name)\u{201D} does not contain a SKILL.md file.")
        case .unreadableLinkTarget(let name, let targetDirectory):
            return String(localized: "\u{201C}\(name)\u{201D} links into \(targetDirectory), which this app cannot read. Import that folder directly instead, or replace the link with a copy.")
        case .cannotLinkManagedFolder(let name):
            return String(localized: "\u{201C}\(name)\u{201D} is already in this agent's skills folder, so there is nothing to link to.")
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
    ///
    /// A symlink whose target cannot be followed is kept rather than skipped.
    /// `.isDirectoryKey` resolves the link, so such an entry would otherwise
    /// fail the directory test and vanish from the list — leaving the user
    /// with a skill that disappeared and no way to clean it up from here.
    func list() throws -> [Skill] {
        guard FileManager.default.fileExists(atPath: skillsDirectoryURL.path) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: skillsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        var skills: [Skill] = []
        for url in contents {
            // `fileExists` follows the link, which is what decides whether
            // there is a skill to read. The `.isDirectoryKey` that
            // `contentsOfDirectory` prefetches comes from the enumeration and
            // does not follow links, so it calls every symlink here a
            // non-directory.
            var isDirectory: ObjCBool = false
            let resolves = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let destination = Self.linkDestination(of: url)

            guard resolves, isDirectory.boolValue else {
                if let destination {
                    skills.append(
                        Skill(
                            directoryName: url.lastPathComponent,
                            name: url.lastPathComponent,
                            summary: "",
                            directoryURL: url,
                            origin: .link(destination: destination, isReadable: false)
                        )
                    )
                }
                continue
            }
            let origin: SkillOrigin = if let destination {
                .link(destination: destination, isReadable: true)
            } else {
                .folder
            }
            let skill = makeSkill(directoryURL: url, origin: origin)
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
        try Self.validateSkillFolder(at: source, named: sourceDirectory.lastPathComponent)
        let destination = try claimDestination(named: sourceDirectory.lastPathComponent)
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

    /// Installs a skill by pointing a symlink at where it already lives,
    /// instead of copying it. The agent reads through the link at runtime, so
    /// one folder — typically in a dotfiles repo — can serve the repo and
    /// every agent at once.
    ///
    /// This app is sandboxed and the open panel's grant dies with the process,
    /// so the caller is responsible for persisting a security-scoped bookmark
    /// for `sourceDirectory`; without one the link still works for the agent
    /// but reads as broken here on the next launch.
    @discardableResult
    func linkSkill(to sourceDirectory: URL) throws -> Skill {
        let source = sourceDirectory.standardizedFileURL
        try Self.validateSkillFolder(
            at: source.resolvingSymlinksInPath(),
            named: source.lastPathComponent
        )
        guard source.deletingLastPathComponent().standardizedFileURL.path
            != skillsDirectoryURL.standardizedFileURL.path
        else {
            throw SkillStoreError.cannotLinkManagedFolder(source.lastPathComponent)
        }
        let destination = try claimDestination(named: source.lastPathComponent)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
        return makeSkill(
            directoryURL: destination,
            origin: .link(destination: source, isReadable: true)
        )
    }

    /// The shared precondition of both import modes: the folder has to hold a
    /// SKILL.md that this app can actually read.
    private static func validateSkillFolder(at source: URL, named name: String) throws {
        let sourceSkillFile = source.appending(path: "SKILL.md")
        guard !FileManager.default.fileExists(atPath: sourceSkillFile.path) else { return }
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
        throw SkillStoreError.notASkillDirectory(name)
    }

    /// Reserves `skills/<name>` for a new entry, creating the skills folder if
    /// this is the first one.
    private func claimDestination(named name: String) throws -> URL {
        let destination = skillsDirectoryURL.appending(path: name)
        guard !Self.entryExists(at: destination) else {
            throw SkillStoreError.skillAlreadyExists(name)
        }
        try FileManager.default.createDirectory(at: skillsDirectoryURL, withIntermediateDirectories: true)
        return destination
    }

    /// Whether anything at all occupies `url`. `fileExists` follows symlinks,
    /// so on its own it reports a link whose target is gone as absent — and
    /// the caller would then try to write over a name that is already taken.
    private static func entryExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Where a symlink points, as an absolute URL. Link text may be relative,
    /// in which case it resolves against the folder holding the link.
    private static func linkDestination(of url: URL) -> URL? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }
        return URL(filePath: target, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
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

    /// Copies a skill folder in, replacing one of the same name. Used when
    /// copying a skill to another agent that already has it.
    @discardableResult
    func replaceSkill(from sourceDirectory: URL) throws -> Skill {
        try clearDestination(named: sourceDirectory.lastPathComponent)
        return try importSkill(from: sourceDirectory)
    }

    /// The link-mode twin of `replaceSkill(from:)`: a linked skill copied to
    /// another agent stays a link there, so both agents keep reading the one
    /// folder the user actually maintains.
    @discardableResult
    func replaceWithLink(to sourceDirectory: URL) throws -> Skill {
        try clearDestination(named: sourceDirectory.standardizedFileURL.lastPathComponent)
        return try linkSkill(to: sourceDirectory)
    }

    private func clearDestination(named name: String) throws {
        let destination = skillsDirectoryURL.appending(path: name)
        if Self.entryExists(at: destination) {
            try FileManager.default.removeItem(at: destination)
        }
    }

    func delete(_ skill: Skill) throws {
        try FileManager.default.removeItem(at: skill.directoryURL)
    }

    // MARK: - Helpers

    private func makeSkill(directoryURL: URL, origin: SkillOrigin = .folder) -> Skill {
        let skillFileURL = directoryURL.appending(path: "SKILL.md")
        let frontmatter = Self.parseFrontmatter(
            (try? String(contentsOf: skillFileURL, encoding: .utf8)) ?? ""
        )
        return Skill(
            directoryName: directoryURL.lastPathComponent,
            name: frontmatter["name"] ?? directoryURL.lastPathComponent,
            summary: frontmatter["description"] ?? "",
            directoryURL: directoryURL,
            origin: origin
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
