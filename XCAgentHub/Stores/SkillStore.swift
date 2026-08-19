import Foundation

enum SkillStoreError: LocalizedError {
    case invalidName
    case skillAlreadyExists(String)
    case notASkillDirectory(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "The skill name must contain at least one letter or number."
        case .skillAlreadyExists(let name):
            return "A skill named \u{201C}\(name)\u{201D} already exists."
        case .notASkillDirectory(let name):
            return "The folder \u{201C}\(name)\u{201D} does not contain a SKILL.md file."
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

    /// Copies a skill directory (must contain SKILL.md) into `skills/`.
    @discardableResult
    func importSkill(from sourceDirectory: URL) throws -> Skill {
        let sourceSkillFile = sourceDirectory.appending(path: "SKILL.md")
        guard FileManager.default.fileExists(atPath: sourceSkillFile.path) else {
            throw SkillStoreError.notASkillDirectory(sourceDirectory.lastPathComponent)
        }
        let destination = skillsDirectoryURL.appending(path: sourceDirectory.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw SkillStoreError.skillAlreadyExists(sourceDirectory.lastPathComponent)
        }
        try FileManager.default.createDirectory(at: skillsDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceDirectory, to: destination)
        return makeSkill(directoryURL: destination)
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
