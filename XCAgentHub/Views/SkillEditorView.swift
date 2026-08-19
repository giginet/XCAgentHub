import SwiftUI

/// Sheet for editing an existing skill's SKILL.md as raw Markdown. New
/// skills are composed with `SkillCreatorView` instead.
struct SkillEditorView: View {
    @Environment(AgentHubViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let agent: AgentKind
    let skill: Skill

    @State private var content = ""
    @State private var errorMessage: String?
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(skill.name)
                    .font(.headline)
                Text(skill.skillFileURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .navigationTitle("Edit Skill")
        .frame(width: 640, height: 520)
        .task {
            loadContentIfNeeded()
        }
    }

    private func loadContentIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        do {
            content = try model.readSkillContent(of: skill, for: agent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try model.saveSkill(content: content, to: skill, for: agent)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
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
