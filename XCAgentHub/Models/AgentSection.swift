import Foundation

/// The two things this app manages for each agent. Picked with the segmented
/// control at the top of the detail pane.
enum AgentSection: String, CaseIterable, Identifiable, Sendable {
    case servers
    case skills

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .servers: return "MCP Servers"
        case .skills: return "Skills"
        }
    }

    var systemImage: String {
        switch self {
        case .servers: return "server.rack"
        case .skills: return "text.book.closed"
        }
    }
}
