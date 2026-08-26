import Foundation
import Testing
@testable import AgentHub

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
