import SwiftUI

struct ContentView: View {
    @Environment(MCPHubViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasFolderAccess {
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    switch model.selection {
                    case .servers(let agent):
                        ServerListView(agent: agent)
                    case .skills(let agent):
                        SkillListView(agent: agent)
                    case nil:
                        ContentUnavailableView(
                            "Select an Item",
                            systemImage: "sidebar.left",
                            description: Text("Choose an agent's MCP servers or skills in the sidebar.")
                        )
                    }
                }
            } else {
                OnboardingView()
            }
        }
        .task {
            model.reloadAll()
        }
        .onChange(of: model.hasFolderAccess) { _, hasAccess in
            if hasAccess {
                model.reloadAll()
            }
        }
        .frame(minWidth: 680, minHeight: 420)
    }
}

#Preview {
    ContentView()
        .environment(MCPHubViewModel.preview)
}
