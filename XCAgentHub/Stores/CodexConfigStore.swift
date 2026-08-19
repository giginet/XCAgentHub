import Foundation
import TOML

/// Store for Codex's `config.toml`. MCP servers live in `[mcp_servers.<name>]`
/// tables with a native `enabled` flag. The whole document is decoded into
/// `TOMLAnyValue` and re-encoded with only the `mcp_servers` table replaced,
/// so every other section keeps its values (TOML comments are not preserved
/// by the encoder, which is why writes are preceded by a backup).
struct CodexConfigStore: AgentConfigStore {
    let configFileURL: URL

    private static let serversKey = "mcp_servers"

    func load() throws -> [MCPServer] {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else { return [] }
        let text = try String(contentsOf: configFileURL, encoding: .utf8)
        let root = try Self.decodeDocument(text)
        guard let serversTable = root[Self.serversKey]?.tableValue else { return [] }

        var servers: [MCPServer] = []
        for (name, value) in serversTable {
            guard let entry = value.tableValue else { continue }
            let isEnabled = entry["enabled"]?.boolValue ?? true
            if let url = entry["url"]?.stringValue {
                servers.append(MCPServer(name: name, transport: .http(url: url), isEnabled: isEnabled))
            } else {
                let command = entry["command"]?.stringValue ?? ""
                let args = entry["args"]?.arrayValue?.compactMap(\.stringValue) ?? []
                var environment: [String: String] = [:]
                if let envTable = entry["env"]?.tableValue {
                    for (key, envValue) in envTable {
                        environment[key] = envValue.stringValue ?? ""
                    }
                }
                servers.append(
                    MCPServer(
                        name: name,
                        transport: .stdio(command: command, args: args, environment: environment),
                        isEnabled: isEnabled
                    )
                )
            }
        }
        return servers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(_ servers: [MCPServer]) throws {
        var root: [String: TOMLAnyValue] = [:]
        if FileManager.default.fileExists(atPath: configFileURL.path) {
            let text = try String(contentsOf: configFileURL, encoding: .utf8)
            root = try Self.decodeDocument(text)
        }

        var serversTable: [String: TOMLAnyValue] = [:]
        for server in servers {
            var entry: [String: TOMLAnyValue] = [:]
            switch server.transport {
            case .stdio(let command, let args, let environment):
                entry["command"] = .string(command)
                entry["args"] = .array(args.map { .string($0) })
                if !environment.isEmpty {
                    entry["env"] = .table(environment.mapValues { .string($0) })
                }
            case .http(let url):
                entry["url"] = .string(url)
            }
            entry["enabled"] = .bool(server.isEnabled)
            serversTable[server.name] = .table(entry)
        }
        root[Self.serversKey] = .table(serversTable)

        try FileManager.default.createDirectory(
            at: configFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let output = try TOMLEncoder().encode(root)
        try output.write(to: configFileURL, options: .atomic)
    }

    private static func decodeDocument(_ text: String) throws -> [String: TOMLAnyValue] {
        do {
            return try TOMLDecoder().decode([String: TOMLAnyValue].self, from: text)
        } catch {
            throw AgentConfigError.malformedConfig(detail: String(describing: error))
        }
    }
}
