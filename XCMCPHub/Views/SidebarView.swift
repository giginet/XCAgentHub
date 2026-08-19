import SwiftUI

/// Sidebar listing the supported coding agents with their server counts.
struct SidebarView: View {
    @Environment(MCPHubViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(AgentKind.allCases, selection: $model.selectedAgent) { agent in
            Label {
                Text(agent.displayName)
            } icon: {
                Image(systemName: agent.systemImage)
            }
            .badge(badge(for: agent))
            .tag(agent)
        }
        .listStyle(.sidebar)
        .navigationTitle("XCMCPHub")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    private func badge(for agent: AgentKind) -> Text? {
        if model.loadError(for: agent) != nil {
            return Text(Image(systemName: "exclamationmark.triangle"))
        }
        guard model.configFileExists(for: agent) else {
            return Text("–")
        }
        return Text("\(model.servers(for: agent).count)")
    }
}

#Preview {
    NavigationSplitView {
        SidebarView()
    } detail: {
        Text("Detail")
    }
    .environment(MCPHubViewModel.preview)
    .frame(width: 640, height: 420)
}
