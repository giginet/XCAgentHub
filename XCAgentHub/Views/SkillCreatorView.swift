import SwiftUI

/// Sheet for creating a new skill. The frontmatter is composed with
/// `SkillFormView` rather than typed by hand.
struct SkillCreatorView: View {
    @Environment(AgentHubViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let agent: AgentKind

    @State private var draft = SkillDraft()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SkillFormView(
                draft: $draft,
                nameFooter: Text("Created as \(agent.skillsDirectoryRelativePath)/\(directoryName.isEmpty ? "…" : directoryName)/SKILL.md. Agents match the description against the task at hand, so say when the skill applies.")
            )

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
                Button("Create") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(directoryName.isEmpty)
            }
            .padding(12)
        }
        .navigationTitle("New Skill")
        .frame(width: 620, height: 700)
    }

    private var directoryName: String {
        SkillStore.sanitizeDirectoryName(draft.name)
    }

    private func save() {
        // The frontmatter name matches the folder, so agents find the skill
        // by either.
        var saved = draft
        saved.name = directoryName
        do {
            try model.createSkill(named: saved.name, content: saved.content, for: agent)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("New Skill") {
    SkillCreatorView(agent: .claudeCode)
        .environment(AgentHubViewModel.preview)
}

#Preview("Antigravity") {
    SkillCreatorView(agent: .gemini)
        .environment(AgentHubViewModel.preview)
}
