import SwiftUI

struct ContentView: View {
    @Environment(AgentHubViewModel.self) private var model

    var body: some View {
        Group {
            if model.hasFolderAccess {
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    if let agent = model.selectedAgent {
                        AgentDetailView(agent: agent)
                    } else {
                        ContentUnavailableView(
                            "Select an Agent",
                            systemImage: "sidebar.left",
                            description: Text("Choose an agent in the sidebar to manage its MCP servers and skills.")
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
        .environment(AgentHubViewModel.preview)
}
