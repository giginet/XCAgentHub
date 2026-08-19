import AppKit
import SwiftUI

/// Lists the skills installed for one agent. Clicking selects,
/// double-clicking (or right-click → Edit…) opens the SKILL.md editor.
struct SkillListView: View {
    @Environment(AgentHubViewModel.self) private var model

    let agent: AgentKind

    @State private var selectedSkillIDs = Set<Skill.ID>()
    @State private var isCreatingSkill = false
    @State private var editingSkill: Skill?
    @State private var skillPendingDeletion: Skill?
    @State private var actionError: String?

    var body: some View {
        let skills = model.skills(for: agent)
        Group {
            if let error = model.skillLoadError(for: agent) {
                ContentUnavailableView {
                    Label("Cannot Read Skills", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        model.reloadSkills(agent)
                    }
                }
            } else if skills.isEmpty {
                ContentUnavailableView {
                    Label("No Skills", systemImage: "text.book.closed")
                } description: {
                    Text("\(agent.displayName) has no skills in \(agent.skillsDirectoryRelativePath) yet.")
                } actions: {
                    Button("Add from Folder…") {
                        importFromPanel()
                    }
                    Button("New Skill…") {
                        isCreatingSkill = true
                    }
                }
            } else {
                List(skills, selection: $selectedSkillIDs) { skill in
                    // The VStack is load-bearing: a custom View struct as the
                    // row root crashes macOS 27 beta's List (ViewListTree
                    // assertion); wrapping it in a builtin container avoids it.
                    VStack {
                        SkillRowView(skill: skill)
                    }
                }
                .contextMenu(forSelectionType: Skill.ID.self) { ids in
                    if let id = ids.first {
                        Button("Edit…") {
                            editingSkill = skill(withID: id)
                        }
                        Button("Delete…", role: .destructive) {
                            skillPendingDeletion = skill(withID: id)
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first {
                        editingSkill = skill(withID: id)
                    }
                }
            }
        }
        .navigationTitle("\(agent.displayName) Skills")
        .navigationSubtitle(agent.skillsDirectoryRelativePath)
        .toolbar {
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") {
                    model.reloadSkills(agent)
                }
                .help("Reload the skills folder from disk")
            }
            ToolbarItem {
                Menu {
                    Button("Add from Folder…") {
                        importFromPanel()
                    }
                    Button("New Skill…") {
                        isCreatingSkill = true
                    }
                } label: {
                    Label("Add Skill", systemImage: "plus")
                }
                .help("Import a skill folder or create a new skill")
            }
        }
        .sheet(isPresented: $isCreatingSkill) {
            SkillEditorView(agent: agent, skill: nil)
        }
        .sheet(item: $editingSkill) { skill in
            SkillEditorView(agent: agent, skill: skill)
        }
        .confirmationDialog(
            "Delete \u{201C}\(skillPendingDeletion?.name ?? "")\u{201D}?",
            isPresented: Binding(
                get: { skillPendingDeletion != nil },
                set: { if !$0 { skillPendingDeletion = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let skill = skillPendingDeletion {
                    do {
                        try model.deleteSkill(skill, for: agent)
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
                skillPendingDeletion = nil
            }
        } message: {
            Text("The skill folder and all of its files will be removed from \(agent.skillsDirectoryRelativePath).")
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK") {
                actionError = nil
            }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func skill(withID id: Skill.ID) -> Skill? {
        model.skills(for: agent).first { $0.id == id }
    }

    /// Lets the user pick a folder containing SKILL.md and copies it into
    /// the agent's skills folder.
    private func importFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a skill folder that contains SKILL.md. The folder will be copied into \(agent.skillsDirectoryRelativePath)."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.importSkill(from: url, for: agent)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// A single row: skill name, description, and folder name.
private struct SkillRowView: View {
    let skill: Skill

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.headline)
                Text(skill.summary.isEmpty ? skill.directoryName : skill.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationSplitView {
        Text("Sidebar")
    } detail: {
        SkillListView(agent: .claudeCode)
    }
    .environment(AgentHubViewModel.preview)
    .frame(width: 720, height: 420)
}

#Preview("Empty") {
    NavigationSplitView {
        Text("Sidebar")
    } detail: {
        SkillListView(agent: .gemini)
    }
    .environment(AgentHubViewModel.preview)
    .frame(width: 720, height: 420)
}
