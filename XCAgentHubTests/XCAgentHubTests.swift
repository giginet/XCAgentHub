import Foundation
import Testing
@testable import XCAgentHub

/// Creates an isolated temporary directory for one test.
private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "XCAgentHubTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
@Suite("JSONAgentConfigStore (Claude)")
struct ClaudeConfigStoreTests {
    private let claudeFixture = """
    {
      "numStartups": 42,
      "installMethod": "xcode",
      "projects": { "/tmp/foo": { "history": ["a", "b"] } },
      "mcpServers": {
        "xcodeproj": {
          "type": "stdio",
          "command": "/usr/local/bin/container",
          "args": ["run", "--rm"],
          "env": { "FOO": "bar" }
        }
      }
    }
    """

    @Test func loadParsesStdioServer() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: ".claude.json")
        try claudeFixture.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONAgentConfigStore(configFileURL: fileURL, dialect: .claude)
        let servers = try store.load()

        #expect(servers.count == 1)
        let server = try #require(servers.first)
        #expect(server.name == "xcodeproj")
        #expect(server.isEnabled)
        #expect(server.transport == .stdio(
            command: "/usr/local/bin/container",
            args: ["run", "--rm"],
            environment: ["FOO": "bar"]
        ))
    }

    @Test func savePreservesUnrelatedKeys() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: ".claude.json")
        try claudeFixture.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONAgentConfigStore(configFileURL: fileURL, dialect: .claude)
        var servers = try store.load()
        servers.append(MCPServer(name: "safari", transport: .http(url: "https://example.com/mcp"), isEnabled: true))
        try store.save(servers)

        let data = try Data(contentsOf: fileURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["numStartups"] as? Int == 42)
        #expect(root["installMethod"] as? String == "xcode")
        #expect(root["projects"] != nil)
        let mcpServers = try #require(root["mcpServers"] as? [String: Any])
        #expect(mcpServers.count == 2)
        let safari = try #require(mcpServers["safari"] as? [String: Any])
        #expect(safari["type"] as? String == "http")
        #expect(safari["url"] as? String == "https://example.com/mcp")
    }

    @Test func disablingMovesServerToDisabledKey() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: ".claude.json")
        try claudeFixture.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONAgentConfigStore(configFileURL: fileURL, dialect: .claude)
        var servers = try store.load()
        servers[0].isEnabled = false
        try store.save(servers)

        let data = try Data(contentsOf: fileURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let enabled = try #require(root["mcpServers"] as? [String: Any])
        #expect(enabled.isEmpty)
        let disabled = try #require(root["_disabledMcpServers"] as? [String: Any])
        #expect(disabled["xcodeproj"] != nil)

        let reloaded = try store.load()
        #expect(reloaded.count == 1)
        #expect(reloaded[0].isEnabled == false)

        // Re-enabling moves it back and removes the stash key.
        var reenabled = reloaded
        reenabled[0].isEnabled = true
        try store.save(reenabled)
        let root2 = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        #expect(root2["_disabledMcpServers"] == nil)
    }

    @Test func loadReturnsEmptyForMissingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONAgentConfigStore(
            configFileURL: directory.appending(path: ".claude.json"),
            dialect: .claude
        )
        #expect(try store.load().isEmpty)
    }
}

@MainActor
@Suite("JSONAgentConfigStore (Gemini)")
struct GeminiConfigStoreTests {
    private let geminiFixture = """
    {
      "theme": "dark",
      "mcpServers": {
        "xcodeproj": {
          "command": "/usr/local/bin/container",
          "args": ["run"]
        }
      },
      "mcp": {
        "serverCommand": "custom-command",
        "excluded": ["ext:other"]
      }
    }
    """

    @Test func disablingUsesNativeExcludedList() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "settings.json")
        try geminiFixture.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONAgentConfigStore(configFileURL: fileURL, dialect: .gemini)
        var servers = try store.load()
        #expect(servers.count == 1)
        #expect(servers[0].isEnabled)

        servers[0].isEnabled = false
        try store.save(servers)

        let data = try Data(contentsOf: fileURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // The definition stays in mcpServers; only the name joins mcp.excluded.
        let mcpServers = try #require(root["mcpServers"] as? [String: Any])
        #expect(mcpServers["xcodeproj"] != nil)
        let mcp = try #require(root["mcp"] as? [String: Any])
        #expect(mcp["serverCommand"] as? String == "custom-command")
        let excluded = try #require(mcp["excluded"] as? [String])
        #expect(excluded.contains("xcodeproj"))
        #expect(excluded.contains("ext:other"))
        #expect(root["theme"] as? String == "dark")

        let reloaded = try store.load()
        #expect(reloaded.count == 1)
        #expect(reloaded[0].isEnabled == false)

        // Re-enabling removes only our entry from mcp.excluded.
        var reenabled = reloaded
        reenabled[0].isEnabled = true
        try store.save(reenabled)
        let root2 = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        let mcp2 = try #require(root2["mcp"] as? [String: Any])
        #expect(mcp2["excluded"] as? [String] == ["ext:other"])
        #expect(mcp2["serverCommand"] as? String == "custom-command")
    }

    @Test func loadMatchesExcludedNamesCaseInsensitively() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "settings.json")
        let fixture = """
        {
          "mcpServers": { "XcodeProj": { "command": "x", "args": [] } },
          "mcp": { "excluded": ["XCODEPROJ"] }
        }
        """
        try fixture.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONAgentConfigStore(configFileURL: fileURL, dialect: .gemini)
        let servers = try store.load()
        #expect(servers.count == 1)
        #expect(servers[0].isEnabled == false)
    }

    @Test func saveMigratesLegacyDisabledStash() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "settings.json")
        let fixture = """
        {
          "mcpServers": {},
          "_disabledMcpServers": { "old": { "command": "x", "args": [] } }
        }
        """
        try fixture.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = JSONAgentConfigStore(configFileURL: fileURL, dialect: .gemini)
        let servers = try store.load()
        #expect(servers.count == 1)
        #expect(servers[0].isEnabled == false)

        try store.save(servers)
        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        #expect(root["_disabledMcpServers"] == nil)
        let mcpServers = try #require(root["mcpServers"] as? [String: Any])
        #expect(mcpServers["old"] != nil)
        let mcp = try #require(root["mcp"] as? [String: Any])
        #expect(mcp["excluded"] as? [String] == ["old"])
    }

    @Test func saveCreatesFileAndDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "gemini/settings.json")

        let store = JSONAgentConfigStore(configFileURL: fileURL, dialect: .gemini)
        try store.save([
            MCPServer(
                name: "xcode",
                transport: .stdio(command: "xcrun", args: ["mcpbridge"], environment: [:]),
                isEnabled: true
            ),
            MCPServer(name: "remote", transport: .http(url: "https://example.com/mcp"), isEnabled: true),
        ])

        let data = try Data(contentsOf: fileURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let mcpServers = try #require(root["mcpServers"] as? [String: Any])
        let xcode = try #require(mcpServers["xcode"] as? [String: Any])
        #expect(xcode["command"] as? String == "xcrun")
        #expect(xcode["args"] as? [String] == ["mcpbridge"])
        // Gemini stdio entries have no "type" key and omit empty env.
        #expect(xcode["type"] == nil)
        #expect(xcode["env"] == nil)
        let remote = try #require(mcpServers["remote"] as? [String: Any])
        #expect(remote["httpUrl"] as? String == "https://example.com/mcp")
        // With every server enabled there is no mcp.excluded to write.
        #expect(root["mcp"] == nil)

        let reloaded = try store.load()
        #expect(reloaded.count == 2)
    }
}

@MainActor
@Suite("SkillStore")
struct SkillStoreTests {
    private func makeStore(in directory: URL) -> SkillStore {
        SkillStore(skillsDirectoryURL: directory.appending(path: "skills"), agent: .claudeCode)
    }

    private func writeSkill(named name: String, content: String, in skillsDirectory: URL) throws {
        let dir = skillsDirectory.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
    }

    @Test func listSkipsHiddenAndInvalidDirectories() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)
        let skillsDir = store.skillsDirectoryURL

        try writeSkill(named: "good-skill", content: """
        ---
        name: good-skill
        description: "Does good things"
        ---

        # Body
        """, in: skillsDir)
        // Hidden directory (like Codex's .system) must be skipped.
        try writeSkill(named: ".system", content: "---\nname: sys\n---\n", in: skillsDir)
        // A directory without SKILL.md must be skipped.
        try FileManager.default.createDirectory(
            at: skillsDir.appending(path: "not-a-skill"),
            withIntermediateDirectories: true
        )
        // A plain file must be skipped.
        try "hi".write(to: skillsDir.appending(path: "note.txt"), atomically: true, encoding: .utf8)

        let skills = try store.list()
        #expect(skills.count == 1)
        let skill = try #require(skills.first)
        #expect(skill.name == "good-skill")
        #expect(skill.summary == "Does good things")
        #expect(skill.directoryName == "good-skill")
    }

    @Test func listReturnsEmptyForMissingDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try makeStore(in: directory).list().isEmpty)
    }

    @Test func createSanitizesNameAndAddsFrontmatter() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let skill = try store.create(named: "My Cool Skill", content: "Do the thing.")
        #expect(skill.directoryName == "my-cool-skill")
        let written = try String(contentsOf: skill.skillFileURL, encoding: .utf8)
        #expect(written.hasPrefix("---\nname: my-cool-skill\n---"))
        #expect(written.contains("Do the thing."))

        // Creating the same skill again fails.
        #expect(throws: SkillStoreError.self) {
            try store.create(named: "my cool skill", content: "again")
        }
        // An unusable name fails.
        #expect(throws: SkillStoreError.self) {
            try store.create(named: "!!!", content: "x")
        }
    }

    @Test func createKeepsExistingFrontmatter() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let original = "---\nname: custom\ndescription: mine\n---\n\nBody"
        let skill = try store.create(named: "custom", content: original)
        #expect(try String(contentsOf: skill.skillFileURL, encoding: .utf8) == original)
        #expect(skill.name == "custom")
        #expect(skill.summary == "mine")
    }

    @Test func importCopiesWholeDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        // Source skill with a nested asset.
        let source = directory.appending(path: "source/tool-skill")
        try FileManager.default.createDirectory(
            at: source.appending(path: "assets"),
            withIntermediateDirectories: true
        )
        try "---\nname: tool-skill\n---\n".write(
            to: source.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "asset".write(
            to: source.appending(path: "assets/data.txt"), atomically: true, encoding: .utf8)

        let skill = try store.importSkill(from: source)
        #expect(skill.directoryName == "tool-skill")
        #expect(FileManager.default.fileExists(
            atPath: store.skillsDirectoryURL.appending(path: "tool-skill/assets/data.txt").path))

        // Importing the same folder again fails.
        #expect(throws: SkillStoreError.self) {
            try store.importSkill(from: source)
        }
        // A folder without SKILL.md fails.
        let empty = directory.appending(path: "source/empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: SkillStoreError.self) {
            try store.importSkill(from: empty)
        }
    }

    @Test func importMaterializesSymlinkedFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A skill laid out the way a dotfiles repo does it: SKILL.md and a
        // reference file are relative symlinks into a sibling folder.
        let shared = directory.appending(path: "shared")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try "---\nname: linked-skill\ndescription: Linked\n---\nBody"
            .write(to: shared.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "reference".write(to: shared.appending(path: "REFERENCE.md"), atomically: true, encoding: .utf8)

        let source = directory.appending(path: "linked-skill")
        try FileManager.default.createDirectory(
            at: source.appending(path: "references"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: source.appending(path: "SKILL.md").path,
            withDestinationPath: "../shared/SKILL.md"
        )
        try FileManager.default.createSymbolicLink(
            atPath: source.appending(path: "references/REFERENCE.md").path,
            withDestinationPath: "../../shared/REFERENCE.md"
        )

        let skillsDirectory = directory.appending(path: "skills")
        let store = SkillStore(skillsDirectoryURL: skillsDirectory, agent: .claudeCode)
        let imported = try store.importSkill(from: source)

        // The copies are real files, not links that broke on the way over.
        let copiedSkillFile = imported.skillFileURL
        let type = try FileManager.default.attributesOfItem(atPath: copiedSkillFile.path)[.type] as? FileAttributeType
        #expect(type == .typeRegular)
        #expect(try String(contentsOf: copiedSkillFile, encoding: .utf8).contains("Body"))
        #expect(try String(
            contentsOf: imported.directoryURL.appending(path: "references/REFERENCE.md"),
            encoding: .utf8
        ) == "reference")

        let listed = try store.list()
        #expect(listed.map(\.name) == ["linked-skill"])
        #expect(listed.first?.summary == "Linked")
    }

    @Test func importRejectsAFolderWhoseSkillFileIsABrokenLink() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appending(path: "broken-skill")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: source.appending(path: "SKILL.md").path,
            withDestinationPath: "../nowhere/SKILL.md"
        )

        let store = SkillStore(
            skillsDirectoryURL: directory.appending(path: "skills"),
            agent: .claudeCode
        )
        #expect(throws: SkillStoreError.self) {
            try store.importSkill(from: source)
        }
    }

    @Test func importReportsALinkTargetItCannotRead() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Stand in for a sandbox denial by making the target unreadable.
        let vault = directory.appending(path: "vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let target = vault.appending(path: "SKILL.md")
        try "---\nname: locked\n---".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: target.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path) }

        let source = directory.appending(path: "locked-skill")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: source.appending(path: "SKILL.md").path,
            withDestinationPath: "../vault/SKILL.md"
        )

        let skillsDirectory = directory.appending(path: "skills")
        let store = SkillStore(skillsDirectoryURL: skillsDirectory, agent: .claudeCode)

        var thrown: SkillStoreError?
        #expect(throws: SkillStoreError.self) {
            do {
                try store.importSkill(from: source)
            } catch let error as SkillStoreError {
                thrown = error
                throw error
            }
        }
        guard case .unreadableLinkTarget(let name, let targetDirectory) = thrown else {
            Issue.record("expected unreadableLinkTarget, got \(String(describing: thrown))")
            return
        }
        #expect(name == "SKILL.md")
        #expect(targetDirectory.hasSuffix("/vault"))

        // A failed import must not leave a half-copied folder behind.
        #expect(try store.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: skillsDirectory.appending(path: "locked-skill").path))
    }

    @Test func saveOverwritesAndDeleteRemoves() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(in: directory)

        let skill = try store.create(named: "editable", content: "v1")
        try store.save(content: "v2 content", to: skill)
        #expect(try store.readContent(of: skill) == "v2 content")

        try store.delete(skill)
        #expect(try store.list().isEmpty)
    }
}

@MainActor
@Suite("ConnectionTester")
struct ConnectionTesterTests {
    @Test func unreachableServerFails() async {
        // Port 1 is never listening locally, so the connection is refused.
        let result = await ConnectionTester.testHTTP(url: "http://127.0.0.1:1/mcp")
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test func invalidURLFails() async {
        #expect(await ConnectionTester.testHTTP(url: "") == .failure(detail: "Invalid URL"))
        #expect(await ConnectionTester.testHTTP(url: "not a url") == .failure(detail: "Invalid URL"))
        #expect(await ConnectionTester.testHTTP(url: "ftp://example.com") == .failure(detail: "Invalid URL"))
    }
}

@MainActor
@Suite("CodexConfigStore")
struct CodexConfigStoreTests {
    private let codexFixture = """
    model = "gpt-5"

    [sandbox_workspace_write]
    network_access = true
    writable_roots = []

    [mcp_servers.xcode-tools]
    command = "xcrun"
    args = ["mcpbridge"]
    enabled = true

    [mcp_servers.xcode-tools.env]
    MCP_XCODE_PID = "663"
    """

    @Test func loadParsesServersAndEnv() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "config.toml")
        try codexFixture.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = CodexConfigStore(configFileURL: fileURL)
        let servers = try store.load()

        #expect(servers.count == 1)
        let server = try #require(servers.first)
        #expect(server.name == "xcode-tools")
        #expect(server.isEnabled)
        #expect(server.transport == .stdio(
            command: "xcrun",
            args: ["mcpbridge"],
            environment: ["MCP_XCODE_PID": "663"]
        ))
    }

    @Test func savePreservesOtherSections() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "config.toml")
        try codexFixture.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = CodexConfigStore(configFileURL: fileURL)
        var servers = try store.load()
        servers.append(
            MCPServer(
                name: "safari",
                transport: .stdio(command: "/usr/bin/safaridriver", args: ["--mcp"], environment: [:]),
                isEnabled: false
            )
        )
        try store.save(servers)

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(text.contains("model = "))
        #expect(text.contains("network_access = true"))

        let reloaded = try store.load()
        #expect(reloaded.count == 2)
        let safari = try #require(reloaded.first { $0.name == "safari" })
        #expect(safari.isEnabled == false)
        #expect(safari.transport == .stdio(
            command: "/usr/bin/safaridriver",
            args: ["--mcp"],
            environment: [:]
        ))
        let xcodeTools = try #require(reloaded.first { $0.name == "xcode-tools" })
        #expect(xcodeTools.isEnabled)
    }

    @Test func saveCreatesFileWhenMissing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "codex/config.toml")

        let store = CodexConfigStore(configFileURL: fileURL)
        try store.save([
            MCPServer(name: "remote", transport: .http(url: "https://example.com/mcp"), isEnabled: true)
        ])

        let reloaded = try store.load()
        #expect(reloaded.count == 1)
        #expect(reloaded[0].transport == .http(url: "https://example.com/mcp"))
    }
}

@Suite("SkillFrontmatter")
struct SkillFrontmatterTests {
    @Test func rendersOnlyTheFieldsThatHaveValues() {
        let frontmatter = SkillFrontmatter(name: "my-skill")

        #expect(frontmatter.rendered() == """
        ---
        name: my-skill
        ---
        """)
    }

    @Test func rendersDescriptionAllowedToolsAndExtraFields() {
        let frontmatter = SkillFrontmatter(
            name: "my-skill",
            summary: "Does a thing",
            allowedTools: ["Bash", " Read ", ""],
            extraFields: [(key: "license", value: "MIT")]
        )

        #expect(frontmatter.rendered() == """
        ---
        name: my-skill
        description: Does a thing
        allowed-tools: Bash, Read
        license: MIT
        ---
        """)
    }

    @Test func skipsBlankAndReservedExtraKeys() {
        let frontmatter = SkillFrontmatter(
            name: "my-skill",
            summary: "Does a thing",
            extraFields: [
                (key: "  ", value: "ignored"),
                (key: "description", value: "duplicate"),
                (key: "license", value: "MIT"),
                (key: "license", value: "Apache-2.0"),
            ]
        )
        let values = SkillStore.parseFrontmatter(frontmatter.rendered())

        #expect(values["description"] == "Does a thing")
        #expect(values["license"] == "MIT")
        #expect(values.count == 3)
    }

    @Test func foldsMultiLineValuesAndQuotesAmbiguousOnes() {
        let frontmatter = SkillFrontmatter(
            name: "my-skill",
            summary: "First line\nsecond line",
            extraFields: [(key: "note", value: "key: value")]
        )
        let rendered = frontmatter.rendered()

        #expect(rendered.contains("description: First line second line"))
        #expect(rendered.contains("note: \"key: value\""))
        #expect(SkillStore.parseFrontmatter(rendered)["note"] == "key: value")
    }
}
