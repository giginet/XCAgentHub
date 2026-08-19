import Foundation

/// The coding agents Xcode supports, each with its own config file format.
enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
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
