import Foundation
import Observation

/// App-wide state: the selected agent and section plus the MCP servers and
/// skills loaded for each agent. Every config mutation backs up the target
/// file first, writes it, then reloads from disk.
@Observable
final class AgentHubViewModel {
    let access: ConfigAccessManager

    /// The agent picked in the sidebar.
    var selectedAgent: AgentKind? = .claudeCode
    /// The section picked with the segmented control in the detail pane.
    var selectedSection: AgentSection = .servers
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
                Skill(
                    directoryName: "deckset-authoring",
                    name: "deckset-authoring",
                    summary: "Write Deckset presentations",
                    directoryURL: URL(filePath: "/tmp/skills/deckset-authoring"),
                    origin: .link(
                        destination: URL(filePath: "/Users/example/dotfiles/skills/deckset-authoring"),
                        isReadable: true
                    )
                ),
                Skill(
                    directoryName: "moved-skill",
                    name: "moved-skill",
                    summary: "",
                    directoryURL: URL(filePath: "/tmp/skills/moved-skill"),
                    origin: .link(
                        destination: URL(filePath: "/Users/example/old/moved-skill"),
                        isReadable: false
                    )
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

    /// True when either the config file or the skills folder failed to load,
    /// so the sidebar can flag the agent without naming the section.
    func hasLoadError(for agent: AgentKind) -> Bool {
        errorsByAgent[agent] != nil || skillErrorsByAgent[agent] != nil
    }

    /// The agent's config file on disk, or nil until folder access is granted.
    func configFileURL(for agent: AgentKind) -> URL? {
        access.rootDirectoryURL.map { agent.configFileURL(in: $0) }
    }

    /// The agent's skills folder on disk, or nil until folder access is
    /// granted. The folder itself may not exist yet.
    func skillsDirectoryURL(for agent: AgentKind) -> URL? {
        access.rootDirectoryURL.map { agent.skillsDirectoryURL(in: $0) }
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

    // MARK: - Copying to another agent

    /// Names the target agent already uses, so the caller can ask before
    /// overwriting them.
    func conflictingServerNames(_ servers: [MCPServer], in target: AgentKind) -> [String] {
        let existing = Set(self.servers(for: target).map(\.name))
        return servers.map(\.name).filter(existing.contains)
    }

    /// Copies servers into another agent's configuration, replacing any of
    /// the same name. Written in one go, so the file is backed up once.
    func copy(_ servers: [MCPServer], to target: AgentKind) {
        var destination = self.servers(for: target)
        for server in servers {
            destination.removeAll { $0.name == server.name }
            destination.append(server)
        }
        persist(destination, for: target)
    }

    func conflictingSkillNames(_ skills: [Skill], in target: AgentKind) -> [String] {
        let existing = Set(self.skills(for: target).map(\.directoryName))
        return skills.map(\.directoryName).filter(existing.contains)
    }

    /// Copies skill folders into another agent's skills folder, replacing
    /// any of the same name. A linked skill is passed along as a link to the
    /// same folder, so the agents keep sharing one copy rather than drifting.
    func copy(_ skills: [Skill], to target: AgentKind) throws {
        guard let root = access.rootDirectoryURL else { return }
        let store = target.makeSkillStore(rootDirectory: root)
        for skill in skills {
            if let destination = skill.linkDestination {
                let copied = try store.replaceWithLink(to: destination)
                // Best effort: the link already works for the agent, and the
                // scope this app is reading through belongs to the original.
                if let bookmark = try? access.makeLinkBookmark(for: destination) {
                    access.rememberLink(at: copied.directoryURL, bookmark: bookmark)
                }
            } else {
                try store.replaceSkill(from: skill.directoryURL)
            }
        }
        reloadSkills(target)
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

    /// Installs a skill as a symlink to where it already lives. The bookmark
    /// comes first: it is the only part that can fail for sandbox reasons, and
    /// failing before the link exists keeps the skills folder clean.
    func linkSkill(to sourceDirectory: URL, for agent: AgentKind) throws {
        guard let root = access.rootDirectoryURL else { return }
        let bookmark = try access.makeLinkBookmark(for: sourceDirectory)
        let skill = try agent.makeSkillStore(rootDirectory: root).linkSkill(to: sourceDirectory)
        access.rememberLink(at: skill.directoryURL, bookmark: bookmark)
        reloadSkills(agent)
    }

    func deleteSkill(_ skill: Skill, for agent: AgentKind) throws {
        guard let root = access.rootDirectoryURL else { return }
        try agent.makeSkillStore(rootDirectory: root).delete(skill)
        access.forgetLink(at: skill.directoryURL)
        reloadSkills(agent)
    }
}
