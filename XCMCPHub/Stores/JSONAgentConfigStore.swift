import Foundation

/// Store for the JSON-based agent configs (Claude Code's `.claude.json` and
/// Gemini's `settings.json`). Both keep MCP servers in a top-level
/// `mcpServers` object; only the entry shape and the disable mechanism
/// differ between the two.
///
/// Disabling:
/// - Claude Code has no native per-server flag, so disabled servers are moved
///   to an app-managed `_disabledMcpServers` sibling key that the agent
///   ignores.
/// - Gemini natively blocks servers listed in `mcp.excluded` (matched
///   case-insensitively), so definitions stay in `mcpServers` and only the
///   name is added to that array.
///
/// All other keys in the file are preserved verbatim.
struct JSONAgentConfigStore: AgentConfigStore {
    enum Dialect {
        case claude
        case gemini
    }

    let configFileURL: URL
    let dialect: Dialect

    private static let serversKey = "mcpServers"
    private static let claudeDisabledKey = "_disabledMcpServers"
    private static let geminiMCPKey = "mcp"
    private static let geminiExcludedKey = "excluded"

    func load() throws -> [MCPServer] {
        guard let root = try Self.readRoot(at: configFileURL) else { return [] }
        var servers = try Self.parseServers(root[Self.serversKey], isEnabled: true)
        // Servers stashed by the Claude mechanism. For Gemini this is a
        // legacy key from earlier app versions, migrated away on save.
        servers += try Self.parseServers(root[Self.claudeDisabledKey], isEnabled: false)
        if dialect == .gemini {
            let excluded = Self.excludedNames(in: root)
            for index in servers.indices
            where excluded.contains(servers[index].name.lowercased()) {
                servers[index].isEnabled = false
            }
        }
        return servers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(_ servers: [MCPServer]) throws {
        var root = try Self.readRoot(at: configFileURL) ?? [:]
        switch dialect {
        case .claude:
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
            root[Self.serversKey] = enabled
            if disabled.isEmpty {
                root.removeValue(forKey: Self.claudeDisabledKey)
            } else {
                root[Self.claudeDisabledKey] = disabled
            }
        case .gemini:
            var all: [String: Any] = [:]
            for server in servers {
                all[server.name] = encode(server)
            }
            root[Self.serversKey] = all
            root.removeValue(forKey: Self.claudeDisabledKey)

            // Rewrite only the entries of `mcp.excluded` that name servers
            // managed here; foreign entries (e.g. extension servers) and the
            // other `mcp` sub-settings stay untouched.
            var mcp = root[Self.geminiMCPKey] as? [String: Any] ?? [:]
            let managedNames = Set(servers.map { $0.name.lowercased() })
            let foreign = (mcp[Self.geminiExcludedKey] as? [String] ?? [])
                .filter { !managedNames.contains($0.lowercased()) }
            let excluded = foreign + servers.filter { !$0.isEnabled }.map(\.name)
            if excluded.isEmpty {
                mcp.removeValue(forKey: Self.geminiExcludedKey)
            } else {
                mcp[Self.geminiExcludedKey] = excluded
            }
            if mcp.isEmpty {
                root.removeValue(forKey: Self.geminiMCPKey)
            } else {
                root[Self.geminiMCPKey] = mcp
            }
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

    /// Lowercased names in Gemini's `mcp.excluded` list.
    private static func excludedNames(in root: [String: Any]) -> Set<String> {
        guard
            let mcp = root[geminiMCPKey] as? [String: Any],
            let excluded = mcp[geminiExcludedKey] as? [String]
        else {
            return []
        }
        return Set(excluded.map { $0.lowercased() })
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
