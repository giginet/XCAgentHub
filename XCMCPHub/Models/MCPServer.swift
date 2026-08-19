import Foundation

/// A single MCP server definition shared across all agent config formats.
struct MCPServer: Identifiable, Hashable, Sendable {
    enum Transport: Hashable, Sendable {
        case stdio(command: String, args: [String], environment: [String: String])
        case http(url: String)
    }

    var name: String
    var transport: Transport
    var isEnabled: Bool

    var id: String { name }
}

extension MCPServer.Transport {
    var isStdio: Bool {
        if case .stdio = self { return true }
        return false
    }

    /// One-line description shown in the server list.
    var summary: String {
        switch self {
        case .stdio(let command, let args, _):
            return ([command] + args).joined(separator: " ")
        case .http(let url):
            return url
        }
    }
}
