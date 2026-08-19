import Foundation
import Observation

/// App-wide state: which agent is selected and the MCP servers loaded from
/// each agent's config file. Every mutation backs up the target file first,
/// writes it, then reloads from disk.
@Observable
final class MCPHubViewModel {
    let access: ConfigAccessManager

    var selectedAgent: AgentKind? = .claudeCode
    private(set) var serversByAgent: [AgentKind: [MCPServer]] = [:]
    private(set) var errorsByAgent: [AgentKind: String] = [:]

    init(
        access: ConfigAccessManager = ConfigAccessManager(),
        initialServers: [AgentKind: [MCPServer]] = [:]
    ) {
        self.access = access
        self.serversByAgent = initialServers
    }

    /// Sample data for SwiftUI previews.
    static var preview: MCPHubViewModel {
        MCPHubViewModel(initialServers: [
            .claudeCode: [
                MCPServer(
                    name: "xcodeproj",
                    transport: .stdio(
                        command: "/usr/local/bin/container",
                        args: ["run", "--rm", "-i"],
                        environment: [:]
                    ),
                    isEnabled: true
                ),
                MCPServer(
                    name: "safari-mcp",
                    transport: .http(url: "https://example.com/mcp"),
                    isEnabled: false
                ),
            ],
            .codex: [
                MCPServer(
                    name: "xcode-tools",
                    transport: .stdio(command: "xcrun", args: ["mcpbridge"], environment: [:]),
                    isEnabled: true
                )
            ],
        ])
    }

    var hasFolderAccess: Bool {
        access.rootDirectoryURL != nil
    }

    func servers(for agent: AgentKind) -> [MCPServer] {
        serversByAgent[agent] ?? []
    }

    func loadError(for agent: AgentKind) -> String? {
        errorsByAgent[agent]
    }

    func configFileExists(for agent: AgentKind) -> Bool {
        guard let root = access.rootDirectoryURL else { return false }
        return FileManager.default.fileExists(atPath: agent.configFileURL(in: root).path)
    }

    func reloadAll() {
        for agent in AgentKind.allCases {
            reload(agent)
        }
    }

    func reload(_ agent: AgentKind) {
        guard let root = access.rootDirectoryURL else { return }
        do {
            serversByAgent[agent] = try agent.makeStore(rootDirectory: root).load()
            errorsByAgent[agent] = nil
        } catch {
            serversByAgent[agent] = []
            errorsByAgent[agent] = error.localizedDescription
        }
    }

    /// Adds a new server or replaces the one named `originalName`.
    func upsert(_ server: MCPServer, replacing originalName: String?, for agent: AgentKind) {
        var servers = servers(for: agent)
        if let originalName {
            servers.removeAll { $0.name == originalName }
        }
        servers.removeAll { $0.name == server.name }
        servers.append(server)
        persist(servers, for: agent)
    }

    func delete(_ server: MCPServer, for agent: AgentKind) {
        var servers = servers(for: agent)
        servers.removeAll { $0.name == server.name }
        persist(servers, for: agent)
    }

    func setEnabled(_ isEnabled: Bool, serverNamed name: String, for agent: AgentKind) {
        var servers = servers(for: agent)
        guard let index = servers.firstIndex(where: { $0.name == name }) else { return }
        servers[index].isEnabled = isEnabled
        persist(servers, for: agent)
    }

    private func persist(_ servers: [MCPServer], for agent: AgentKind) {
        guard let root = access.rootDirectoryURL else { return }
        let store = agent.makeStore(rootDirectory: root)
        do {
            try BackupManager.backUpIfNeeded(fileURL: store.configFileURL, agent: agent)
            try store.save(servers)
            errorsByAgent[agent] = nil
        } catch {
            errorsByAgent[agent] = error.localizedDescription
        }
        reload(agent)
    }
}
