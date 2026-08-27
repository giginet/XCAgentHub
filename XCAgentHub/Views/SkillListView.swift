import AppKit
import SwiftUI

/// Lists the skills installed for one agent. Clicking selects,
/// double-clicking (or right-click → Edit…) opens the SKILL.md editor. The
/// bottom bar deletes the selection or copies it to another agent.
struct SkillListView: View {
    @Environment(AgentHubViewModel.self) private var model

    let agent: AgentKind

    @State private var selectedSkillIDs = Set<Skill.ID>()
    @State private var isCreatingSkill = false
    @State private var editingSkill: Skill?
    @State private var skillsPendingDeletion: [Skill] = []
    @State private var pendingCopy: PendingCopy?

    /// A copy waiting on the user, because the target agent already has
    /// skills with these folder names.
    private struct PendingCopy: Identifiable {
        let id = UUID()
        var target: AgentKind
        var skills: [Skill]
        var conflicts: [String]
    }
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
                        importFromPanel(mode: .copy)
                    }
                    Button("Link to Folder…") {
                        importFromPanel(mode: .link)
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
                Button("Show in Finder", systemImage: "finder") {
                    if let url = model.skillsDirectoryURL(for: agent) {
                        FinderReveal.show(url)
                    }
                }
                .disabled(model.skillsDirectoryURL(for: agent) == nil)
                .help("Show \(agent.skillsDirectoryRelativePath) in Finder")
            }
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") {
                    model.reloadSkills(agent)
                }
                .help("Reload the skills folder from disk")
            }
            ToolbarItem {
                Menu {
                    Button("Add from Folder…") {
                        importFromPanel(mode: .copy)
                    }
                    Button("Link to Folder…") {
                        importFromPanel(mode: .link)
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
            deletionMessage
        }
        .confirmationDialog(
            Text("Replace \(pendingCopy?.conflicts.count ?? 0) skills in \(pendingCopy?.target.displayName ?? "")?"),
            isPresented: Binding(
                get: { pendingCopy != nil },
                set: { if !$0 { pendingCopy = nil } }
            ),
            presenting: pendingCopy
        ) { copy in
            Button("Replace", role: .destructive) {
                performCopy(copy.skills, to: copy.target)
                pendingCopy = nil
            }
        } message: { copy in
            Text("\(copy.conflicts.joined(separator: ", ")) already exist there. The existing folders are removed first.")
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
                if let id = ids.first, let skill = skill(withID: id), !skill.isBrokenLink {
                    editingSkill = skill
                }
            }

            Divider()
            bottomBar(skillCount: skills.count)
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<Skill.ID>) -> some View {
        if let id = ids.first, let skill = skill(withID: id) {
            Button("Edit…") {
                editingSkill = skill
            }
            .disabled(skill.isBrokenLink)
            if let destination = skill.linkDestination {
                Button("Reveal Original in Finder") {
                    FinderReveal.show(destination)
                }
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
            .help(selectedSkillIDs.isEmpty ? Text("Select a skill to delete it") : Text("Delete the selected skills"))
            copyMenu
            Spacer()
            Text("\(skillCount) skills")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Copies the selection into another agent's skills folder.
    private var copyMenu: some View {
        Menu {
            ForEach(AgentKind.allCases.filter { $0 != agent }) { target in
                Button(target.displayName) {
                    copy(to: target)
                }
            }
        } label: {
            Label("Copy to Another Agent", systemImage: "document.on.document")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .labelStyle(.iconOnly)
        .fixedSize()
        .disabled(selectedSkillIDs.isEmpty)
        .help(selectedSkillIDs.isEmpty ? Text("Select a skill to copy it") : Text("Copy the selected skills to another agent"))
    }

    /// Copies straight away unless the target already has a skill folder of
    /// the same name, which is worth asking about before replacing it.
    private func copy(to target: AgentKind) {
        let selected = skills(withIDs: selectedSkillIDs)
        let conflicts = model.conflictingSkillNames(selected, in: target)
        guard !conflicts.isEmpty else {
            performCopy(selected, to: target)
            return
        }
        pendingCopy = PendingCopy(target: target, skills: selected, conflicts: conflicts)
    }

    private func performCopy(_ skills: [Skill], to target: AgentKind) {
        do {
            try model.copy(skills, to: target)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var deletionTitle: Text {
        if skillsPendingDeletion.count == 1, let skill = skillsPendingDeletion.first {
            return Text("Delete \u{201C}\(skill.name)\u{201D}?")
        }
        return Text("Delete \(skillsPendingDeletion.count) skills?")
    }

    /// Deleting a link removes only the link, so promising that the files go
    /// away would be a lie for exactly the skills the user cares most about.
    private var deletionMessage: Text {
        let linked = skillsPendingDeletion.filter { $0.linkDestination != nil }.count
        if linked == 0 {
            return Text("The skill folder and all of its files will be removed from \(agent.skillsDirectoryRelativePath).")
        }
        if linked == skillsPendingDeletion.count {
            return Text("Only the link in \(agent.skillsDirectoryRelativePath) is removed. The folder it points to is left alone.")
        }
        return Text("Copied skills are removed from \(agent.skillsDirectoryRelativePath) with all of their files. For linked skills only the link is removed.")
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

    /// Lets the user pick a folder containing SKILL.md and installs it into
    /// the agent's skills folder, either as a copy or as a link to where it
    /// already lives.
    private func importFromPanel(mode: ImportMode) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        // Skills usually live under dot-directories such as ~/.claude/skills,
        // so start with hidden files visible.
        panel.showsHiddenFiles = true
        panel.message = switch mode {
        case .copy:
            String(
                localized: "Select a skill folder that contains SKILL.md. The folder will be copied into \(agent.skillsDirectoryRelativePath)."
            )
        case .link:
            String(
                localized: "Select a skill folder that contains SKILL.md. It stays where it is and \(agent.skillsDirectoryRelativePath) gets a link to it, so editing the skill here edits that folder."
            )
        }
        panel.prompt = switch mode {
        case .copy: String(localized: "Import")
        case .link: String(localized: "Link")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch mode {
            case .copy:
                try model.importSkill(from: url, for: agent)
            case .link:
                try model.linkSkill(to: url, for: agent)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// How a picked folder gets installed.
private enum ImportMode {
    case copy
    case link
}

/// A single row: skill name, description, and — for a linked skill — the
/// folder it points at. That last line is not decoration: editing a linked
/// skill writes into that folder, so the row says where the writes land.
private struct SkillRowView: View {
    let skill: Skill

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(skill.isBrokenLink ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.headline)
                Text(skill.summary.isEmpty ? skill.directoryName : skill.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let destination = skill.linkDestination {
                    linkLine(to: destination)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        if skill.isBrokenLink { return "questionmark.folder" }
        return skill.linkDestination == nil ? "text.book.closed" : "link"
    }

    private func linkLine(to destination: URL) -> some View {
        let path = ConfigAccessManager.abbreviatingHome(destination.path)
        return Group {
            if skill.isBrokenLink {
                Text("Cannot read \(path)")
                    .foregroundStyle(.orange)
            } else {
                Text(path)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(destination.path)
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
