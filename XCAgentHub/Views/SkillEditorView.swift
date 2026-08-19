import SwiftUI

/// Sheet for creating a new skill or editing an existing skill's SKILL.md.
struct SkillEditorView: View {
    @Environment(AgentHubViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let agent: AgentKind
    /// nil creates a new skill; otherwise this skill's SKILL.md is edited.
    let skill: Skill?

    @State private var name: String
    @State private var content: String
    @State private var errorMessage: String?
    @State private var didLoad = false

    init(agent: AgentKind, skill: Skill?) {
        self.agent = agent
        self.skill = skill
        _name = State(initialValue: "")
        _content = State(initialValue: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let skill {
                    Text(skill.name)
                        .font(.headline)
                    Text(skill.skillFileURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    TextField("Name", text: $name, prompt: Text("my-skill"))
                        .font(.body.monospaced())
                    Text("Created as \(agent.skillsDirectoryRelativePath)/\(SkillStore.sanitizeDirectoryName(name).isEmpty ? "…" : SkillStore.sanitizeDirectoryName(name))/SKILL.md. A name frontmatter is added when the body has none.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            Divider()
            TextEditor(text: $content)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)

            Divider()
            HStack {
                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .help(errorMessage)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(skill == nil ? "Create" : "Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(skill == nil && SkillStore.sanitizeDirectoryName(name).isEmpty)
            }
            .padding(12)
        }
        .navigationTitle(skill == nil ? "New Skill" : "Edit Skill")
        .frame(width: 640, height: 520)
        .task {
            loadContentIfNeeded()
        }
    }

    private func loadContentIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let skill else { return }
        do {
            content = try model.readSkillContent(of: skill, for: agent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            if let skill {
                try model.saveSkill(content: content, to: skill, for: agent)
            } else {
                try model.createSkill(named: name, content: content, for: agent)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("New") {
    SkillEditorView(agent: .claudeCode, skill: nil)
        .environment(AgentHubViewModel.preview)
}

#Preview("Edit") {
    SkillEditorView(
        agent: .claudeCode,
        skill: Skill(
            directoryName: "compose-app-icon",
            name: "compose-app-icon",
            summary: "Author and validate Apple Icon Composer .icon packages",
            directoryURL: URL(filePath: "/tmp/skills/compose-app-icon")
        )
    )
    .environment(AgentHubViewModel.preview)
}
