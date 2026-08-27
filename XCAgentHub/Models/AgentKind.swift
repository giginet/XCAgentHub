import Foundation

/// The coding agents Xcode supports, each with its own config file format.
enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case gemini

    var id: String { rawValue }

    /// What the agent calls itself today. The enum case and the paths below
    /// stay `gemini`: that is still the folder Xcode reads, only the product
    /// was renamed.
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Antigravity"
        }
    }

    var systemImage: String {
        switch self {
        case .claudeCode: return "asterisk"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .gemini: return "sparkle"
        }
    }

    /// Path of the agent's config file relative to the CodingAssistant folder.
    var configFileRelativePath: String {
        switch self {
        case .claudeCode: return "ClaudeAgentConfig/.claude.json"
        case .codex: return "codex/config.toml"
        case .gemini: return "gemini/settings.json"
        }
    }

    func configFileURL(in rootDirectory: URL) -> URL {
        rootDirectory.appending(path: configFileRelativePath)
    }

    /// Path of the agent's skills folder relative to the CodingAssistant
    /// folder. All three agents use the same `skills/<name>/SKILL.md` layout.
    var skillsDirectoryRelativePath: String {
        switch self {
        case .claudeCode: return "ClaudeAgentConfig/skills"
        case .codex: return "codex/skills"
        case .gemini: return "gemini/skills"
        }
    }

    func skillsDirectoryURL(in rootDirectory: URL) -> URL {
        rootDirectory.appending(path: skillsDirectoryRelativePath)
    }

    func makeSkillStore(rootDirectory: URL) -> SkillStore {
        SkillStore(skillsDirectoryURL: skillsDirectoryURL(in: rootDirectory), agent: self)
    }

    func makeStore(rootDirectory: URL) -> any AgentConfigStore {
        let url = configFileURL(in: rootDirectory)
        switch self {
        case .claudeCode:
            return JSONAgentConfigStore(configFileURL: url, dialect: .claude)
        case .codex:
            return CodexConfigStore(configFileURL: url)
        case .gemini:
            return JSONAgentConfigStore(configFileURL: url, dialect: .gemini)
        }
    }
}
