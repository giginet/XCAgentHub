import Foundation
import Testing
@testable import XCMCPHub

/// Creates an isolated temporary directory for one test.
private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "XCMCPHubTests-\(UUID().uuidString)")
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
