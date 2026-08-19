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
                    if let agent = model.selectedAgent {
                        ServerListView(agent: agent)
                    } else {
                        ContentUnavailableView(
                            "Select an Agent",
                            systemImage: "sidebar.left",
                            description: Text("Choose a coding agent in the sidebar to manage its MCP servers.")
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
        .frame(minWidth: 640, minHeight: 400)
    }
}

#Preview {
    ContentView()
        .environment(MCPHubViewModel.preview)
}
