import SwiftUI

/// Detail pane for one agent. A segmented control in the toolbar switches
/// between the agent's MCP servers and its skills; each section brings its
/// own title, subtitle, and toolbar buttons.
struct AgentDetailView: View {
    @Environment(AgentHubViewModel.self) private var model

    let agent: AgentKind

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.selectedSection {
            case .servers:
                ServerListView(agent: agent)
            case .skills:
                SkillListView(agent: agent)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $model.selectedSection) {
                    ForEach(AgentSection.allCases) { section in
                        Text(section.displayName).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

#Preview("MCP Servers") {
    @Previewable @State var model = AgentHubViewModel.preview
    NavigationSplitView {
        SidebarView()
    } detail: {
        AgentDetailView(agent: .claudeCode)
    }
    .environment(model)
    .frame(width: 760, height: 460)
}

#Preview("Skills") {
    @Previewable @State var model: AgentHubViewModel = {
        let model = AgentHubViewModel.preview
        model.selectedSection = .skills
        return model
    }()
    NavigationSplitView {
        SidebarView()
    } detail: {
        AgentDetailView(agent: .claudeCode)
    }
    .environment(model)
    .frame(width: 760, height: 460)
}
