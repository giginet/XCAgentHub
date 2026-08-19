import Foundation

/// Store for the JSON-based agent configs (Claude Code's `.claude.json` and
/// Gemini's `settings.json`). Both keep MCP servers in a top-level
/// `mcpServers` object; only the entry shape differs between the two.
///
/// Neither format has a native per-server enabled flag, so disabled servers
/// are moved to an app-managed `_disabledMcpServers` sibling key that both
/// agents ignore. All other keys in the file are preserved verbatim.
struct JSONAgentConfigStore: AgentConfigStore {
    enum Dialect {
        case claude
        case gemini
    }

    let configFileURL: URL
    let dialect: Dialect

    private static let enabledKey = "mcpServers"
    private static let disabledKey = "_disabledMcpServers"

    func load() throws -> [MCPServer] {
        guard let root = try Self.readRoot(at: configFileURL) else { return [] }
        var servers: [MCPServer] = []
        servers += try Self.parseServers(root[Self.enabledKey], isEnabled: true)
        servers += try Self.parseServers(root[Self.disabledKey], isEnabled: false)
        return servers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(_ servers: [MCPServer]) throws {
        var root = try Self.readRoot(at: configFileURL) ?? [:]

        var enabled: [String: Any] = [:]
        var disabled: [String: Any] = [:]
        for server in servers {
            let entry = encode(server)
            if server.isEnabled {
                enabled[server.name] = entry
            } else {
                disabled[server.name] = entry
            }
        }
        root[Self.enabledKey] = enabled
        if disabled.isEmpty {
            root.removeValue(forKey: Self.disabledKey)
        } else {
            root[Self.disabledKey] = disabled
        }

        try FileManager.default.createDirectory(
            at: configFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configFileURL, options: .atomic)
    }

    // MARK: - Parsing

    private static func readRoot(at url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentConfigError.malformedConfig(detail: "expected a top-level JSON object")
        }
        return root
    }

    private static func parseServers(_ value: Any?, isEnabled: Bool) throws -> [MCPServer] {
        guard let value else { return [] }
        guard let dictionary = value as? [String: Any] else {
            throw AgentConfigError.malformedConfig(detail: "mcpServers must be an object")
        }
        return dictionary.compactMap { name, rawEntry in
            guard let entry = rawEntry as? [String: Any] else { return nil }
            return decode(name: name, entry: entry, isEnabled: isEnabled)
        }
    }

    private static func decode(name: String, entry: [String: Any], isEnabled: Bool) -> MCPServer {
        if let url = (entry["url"] as? String) ?? (entry["httpUrl"] as? String) {
            return MCPServer(name: name, transport: .http(url: url), isEnabled: isEnabled)
        }
        let command = entry["command"] as? String ?? ""
        let args = entry["args"] as? [String] ?? []
        let environment = entry["env"] as? [String: String] ?? [:]
        return MCPServer(
            name: name,
            transport: .stdio(command: command, args: args, environment: environment),
            isEnabled: isEnabled
        )
    }

    private func encode(_ server: MCPServer) -> [String: Any] {
        switch (server.transport, dialect) {
        case (.stdio(let command, let args, let environment), .claude):
            return [
                "type": "stdio",
                "command": command,
                "args": args,
                "env": environment,
            ]
        case (.stdio(let command, let args, let environment), .gemini):
            var entry: [String: Any] = ["command": command, "args": args]
            if !environment.isEmpty {
                entry["env"] = environment
            }
            return entry
        case (.http(let url), .claude):
            return ["type": "http", "url": url]
        case (.http(let url), .gemini):
            return ["httpUrl": url]
        }
    }
}
