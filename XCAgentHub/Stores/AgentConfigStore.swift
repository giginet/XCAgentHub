import Foundation

/// Reads and writes MCP server definitions for one agent's config file.
/// Implementations must preserve every unrelated key in the file.
protocol AgentConfigStore {
    var configFileURL: URL { get }
    func load() throws -> [MCPServer]
    func save(_ servers: [MCPServer]) throws
}

enum AgentConfigError: LocalizedError {
    case malformedConfig(detail: String)

    var errorDescription: String? {
        switch self {
        case .malformedConfig(let detail):
            return "The configuration file could not be parsed: \(detail)"
        }
    }
}
