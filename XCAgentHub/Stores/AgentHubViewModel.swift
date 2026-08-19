import Foundation
import Observation

/// What the sidebar can select: one feature of one agent.
enum SidebarItem: Hashable {
    case servers(AgentKind)
    case skills(AgentKind)
}

/// App-wide state: the sidebar selection plus the MCP servers and skills
/// loaded for each agent. Every config mutation backs up the target file
/// first, writes it, then reloads from disk.
@Observable
final class AgentHubViewModel {
    let access: ConfigAccessManager

    var selection: SidebarItem? = .servers(.claudeCode)
    private(set) var serversByAgent: [AgentKind: [MCPServer]] = [:]
    private(set) var errorsByAgent: [AgentKind: String] = [:]
    private(set) var skillsByAgent: [AgentKind: [Skill]] = [:]
    private(set) var skillErrorsByAgent: [AgentKind: String] = [:]

    init(
        access: ConfigAccessManager = ConfigAccessManager(),
        initialServers: [AgentKind: [MCPServer]] = [:],
        initialSkills: [AgentKind: [Skill]] = [:]
    ) {
        self.access = access
        self.serversByAgent = initialServers
        self.skillsByAgent = initialSkills
    }

    /// Sample data for SwiftUI previews.
    static var preview: AgentHubViewModel {
        AgentHubViewModel(initialServers: [
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
        ], initialSkills: [
            .claudeCode: [
                Skill(
                    directoryName: "compose-app-icon",
                    name: "compose-app-icon",
                    summary: "Author and validate Apple Icon Composer .icon packages",
                    directoryURL: URL(filePath: "/tmp/skills/compose-app-icon")
                ),
                Skill(
                    directoryName: "modernize-tests",
                    name: "modernize-tests",
                    summary: "Migrate test suites to Swift Testing",
                    directoryURL: URL(filePath: "/tmp/skills/modernize-tests")
                ),
            ]
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
            reloadSkills(agent)
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

    // MARK: - Skills

    func skills(for agent: AgentKind) -> [Skill] {
        skillsByAgent[agent] ?? []
    }

    func skillLoadError(for agent: AgentKind) -> String? {
        skillErrorsByAgent[agent]
    }

    func reloadSkills(_ agent: AgentKind) {
        guard let root = access.rootDirectoryURL else { return }
        do {
            skillsByAgent[agent] = try agent.makeSkillStore(rootDirectory: root).list()
            skillErrorsByAgent[agent] = nil
        } catch {
            skillsByAgent[agent] = []
            skillErrorsByAgent[agent] = error.localizedDescription
        }
    }

    func readSkillContent(of skill: Skill, for agent: AgentKind) throws -> String {
        guard let root = access.rootDirectoryURL else { return "" }
        return try agent.makeSkillStore(rootDirectory: root).readContent(of: skill)
    }

    func saveSkill(content: String, to skill: Skill, for agent: AgentKind) throws {
        guard let root = access.rootDirectoryURL else { return }
        try agent.makeSkillStore(rootDirectory: root).save(content: content, to: skill)
        reloadSkills(agent)
    }

    func createSkill(named name: String, content: String, for agent: AgentKind) throws {
        guard let root = access.rootDirectoryURL else { return }
        try agent.makeSkillStore(rootDirectory: root).create(named: name, content: content)
        reloadSkills(agent)
    }

    func importSkill(from sourceDirectory: URL, for agent: AgentKind) throws {
        guard let root = access.rootDirectoryURL else { return }
        try agent.makeSkillStore(rootDirectory: root).importSkill(from: sourceDirectory)
        reloadSkills(agent)
    }

    func deleteSkill(_ skill: Skill, for agent: AgentKind) throws {
        guard let root = access.rootDirectoryURL else { return }
        try agent.makeSkillStore(rootDirectory: root).delete(skill)
        reloadSkills(agent)
    }
}
