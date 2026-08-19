import SwiftUI

/// Sidebar listing the supported agents. What to show for the selected agent
/// (MCP servers or skills) is picked in the detail pane instead.
struct SidebarView: View {
    @Environment(AgentHubViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(AgentKind.allCases, selection: $model.selectedAgent) { agent in
            Label(agent.displayName, systemImage: agent.systemImage)
                .badge(badge(for: agent))
                .tag(agent)
        }
        .listStyle(.sidebar)
        .navigationTitle("XCAgentHub")
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
    }

    private func badge(for agent: AgentKind) -> Text? {
        guard model.hasLoadError(for: agent) else { return nil }
        return Text(Image(systemName: "exclamationmark.triangle"))
    }
}

#Preview {
    NavigationSplitView {
        SidebarView()
    } detail: {
        Text("Detail")
    }
    .environment(AgentHubViewModel.preview)
    .frame(width: 680, height: 480)
}
