import Foundation

enum ConnectionTestResult: Equatable {
    case success(detail: String)
    case failure(detail: String)
}

/// Health-checks an HTTP MCP server by sending a JSON-RPC `initialize`
/// request, as defined by the MCP streamable HTTP transport. stdio servers
/// are not testable from a sandboxed app, so only HTTP is supported.
struct ConnectionTester {
    static let timeout: TimeInterval = 5

    static func testHTTP(url urlString: String) async -> ConnectionTestResult {
        guard
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return .failure(detail: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-06-18",
                "capabilities": [String: Any](),
                "clientInfo": ["name": "XCAgentHub", "version": "1.0"],
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(detail: "Unexpected response")
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(detail: "HTTP \(http.statusCode)")
            }
            if let name = serverName(in: data) {
                return .success(detail: "Connected to \(name)")
            }
            return .success(detail: "Server responded (HTTP \(http.statusCode))")
        } catch {
            return .failure(detail: error.localizedDescription)
        }
    }

    /// Extracts `result.serverInfo.name` from an initialize response when the
    /// body is plain JSON. SSE-framed responses just fall back to the status.
    private static func serverName(in data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = root["result"] as? [String: Any],
            let serverInfo = result["serverInfo"] as? [String: Any]
        else {
            return nil
        }
        return serverInfo["name"] as? String
    }
}
