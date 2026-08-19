import AppKit
import SwiftUI

/// Lists the skills installed for one agent. Clicking selects,
/// double-clicking (or right-click → Edit…) opens the SKILL.md editor, and
/// the trash button in the bottom bar deletes the selection.
struct SkillListView: View {
    @Environment(AgentHubViewModel.self) private var model

    let agent: AgentKind

    @State private var selectedSkillIDs = Set<Skill.ID>()
    @State private var isCreatingSkill = false
    @State private var editingSkill: Skill?
    @State private var skillsPendingDeletion: [Skill] = []
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
                skillList(skills)
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
            SkillCreatorView(agent: agent)
        }
        .sheet(item: $editingSkill) { skill in
            SkillEditorView(agent: agent, skill: skill)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { !skillsPendingDeletion.isEmpty },
                set: { if !$0 { skillsPendingDeletion = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deletePendingSkills()
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

    private func skillList(_ skills: [Skill]) -> some View {
        VStack(spacing: 0) {
            List(skills, selection: $selectedSkillIDs) { skill in
                // The VStack is load-bearing: a custom View struct as the row
                // root crashes macOS 27 beta's List (ViewListTree assertion);
                // wrapping it in a builtin container avoids it.
                VStack {
                    SkillRowView(skill: skill)
                }
            }
            .contextMenu(forSelectionType: Skill.ID.self) { ids in
                contextMenu(for: ids)
            } primaryAction: { ids in
                if let id = ids.first {
                    editingSkill = skill(withID: id)
                }
            }

            Divider()
            bottomBar(skillCount: skills.count)
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<Skill.ID>) -> some View {
        if let id = ids.first {
            Button("Edit…") {
                editingSkill = skill(withID: id)
            }
        }
        if !ids.isEmpty {
            Button("Delete…", role: .destructive) {
                skillsPendingDeletion = skills(withIDs: ids)
            }
        }
    }

    /// Trash button plus the skill count, mirroring the bottom bar of a
    /// macOS list editor.
    private func bottomBar(skillCount: Int) -> some View {
        HStack {
            Button("Delete", systemImage: "trash") {
                skillsPendingDeletion = skills(withIDs: selectedSkillIDs)
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .disabled(selectedSkillIDs.isEmpty)
            .help(selectedSkillIDs.isEmpty ? "Select a skill to delete it" : "Delete the selected skills")
            Spacer()
            Text(skillCount == 1 ? "1 skill" : "\(skillCount) skills")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var deletionTitle: String {
        if skillsPendingDeletion.count == 1, let skill = skillsPendingDeletion.first {
            return "Delete \u{201C}\(skill.name)\u{201D}?"
        }
        return "Delete \(skillsPendingDeletion.count) skills?"
    }

    /// Deletes each pending skill, keeping the first failure to show.
    private func deletePendingSkills() {
        for skill in skillsPendingDeletion {
            do {
                try model.deleteSkill(skill, for: agent)
            } catch {
                actionError = actionError ?? error.localizedDescription
            }
        }
        selectedSkillIDs.subtract(skillsPendingDeletion.map(\.id))
        skillsPendingDeletion = []
    }

    private func skill(withID id: Skill.ID) -> Skill? {
        model.skills(for: agent).first { $0.id == id }
    }

    private func skills(withIDs ids: Set<Skill.ID>) -> [Skill] {
        model.skills(for: agent).filter { ids.contains($0.id) }
    }

    /// Lets the user pick a folder containing SKILL.md and copies it into
    /// the agent's skills folder.
    private func importFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        // Skills usually live under dot-directories such as ~/.claude/skills,
        // so start with hidden files visible.
        panel.showsHiddenFiles = true
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
