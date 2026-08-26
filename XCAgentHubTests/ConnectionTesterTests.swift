import Foundation
import Testing
@testable import AgentHub

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

        // The detail text is localized, so assert on the outcome, not the wording.
        @Test(arguments: ["", "not a url", "ftp://example.com"])
        func invalidURLFails(url: String) async {
            let result = await ConnectionTester.testHTTP(url: url)
            guard case .failure = result else {
                Issue.record("expected failure for \u{201C}\(url)\u{201D}, got \(result)")
                return
            }
        }
}
