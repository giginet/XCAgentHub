import SwiftUI

/// Sidebar with one section per agent, each offering its MCP servers and
/// its skills.
struct SidebarView: View {
    @Environment(MCPHubViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(AgentKind.allCases) { agent in
                Section {
                    Label("MCP Servers", systemImage: "server.rack")
                        .badge(serverBadge(for: agent))
                        .tag(SidebarItem.servers(agent))
                    Label("Skills", systemImage: "text.book.closed")
                        .badge(Text("\(model.skills(for: agent).count)"))
                        .tag(SidebarItem.skills(agent))
                } header: {
                    Label(agent.displayName, systemImage: agent.systemImage)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("XCMCPHub")
        .navigationSplitViewColumnWidth(min: 190, ideal: 210)
    }

    private func serverBadge(for agent: AgentKind) -> Text? {
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
    .frame(width: 680, height: 480)
}
