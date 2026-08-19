import SwiftUI

/// Sheet for editing an existing skill's SKILL.md. The frontmatter is edited
/// with the same structured form as a new skill; a file whose YAML the form
/// cannot represent falls back to editing the raw Markdown, so nothing is
/// silently dropped.
struct SkillEditorView: View {
    private enum Mode {
        case loading
        case form
        /// Raw Markdown, because the frontmatter carries YAML that rendering
        /// the form back out would destroy.
        case raw
    }

    @Environment(AgentHubViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let agent: AgentKind
    let skill: Skill

    @State private var mode = Mode.loading
    @State private var draft = SkillDraft()
    @State private var rawContent = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .form:
                SkillFormView(draft: $draft, nameFooter: Text(footerText))
            case .raw:
                rawEditor
            }

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
                .disabled(mode == .loading)
            }
            .padding(12)
        }
        .navigationTitle("Edit Skill")
        .frame(width: 620, height: 700)
        .task {
            loadContentIfNeeded()
        }
    }

    private var footerText: String {
        "Stored in \(agent.skillsDirectoryRelativePath)/\(skill.directoryName)/SKILL.md. The name here is the frontmatter; the folder keeps its own name."
    }

    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Edited as Markdown", systemImage: "curlybraces")
                    .font(.headline)
                Text("This SKILL.md uses YAML the form cannot represent — a comment, a multi-line value, or a nested map. Editing the text keeps it intact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            Divider()
            TextEditor(text: $rawContent)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
        }
    }

    private func loadContentIfNeeded() {
        guard mode == .loading else { return }
        do {
            let content = try model.readSkillContent(of: skill, for: agent)
            if let parsed = SkillFrontmatter.parse(content) {
                draft = SkillDraft(frontmatter: parsed.frontmatter, body: parsed.body)
                mode = .form
            } else {
                rawContent = content
                mode = .raw
            }
        } catch {
            rawContent = ""
            mode = .raw
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try model.saveSkill(content: mode == .raw ? rawContent : draft.content, to: skill, for: agent)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Writes a SKILL.md under the temporary directory so the previews below
/// exercise the real load path instead of an empty editor.
private func previewSkill(named name: String, content: String) -> Skill {
    let directory = URL(filePath: NSTemporaryDirectory())
        .appending(path: "XCAgentHubPreviews/\(name)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? Data(content.utf8).write(to: directory.appending(path: "SKILL.md"))
    return Skill(directoryName: name, name: name, summary: "", directoryURL: directory)
}

#Preview("Form") {
    SkillEditorView(
        agent: .claudeCode,
        skill: previewSkill(named: "compose-app-icon", content: """
        ---
        name: compose-app-icon
        description: Author and validate Apple Icon Composer .icon packages
        allowed-tools: Bash, Read
        license: MIT
        ---

        # compose-app-icon

        Start from the bundled JSON Schema.
        """)
    )
    .environment(AgentHubViewModel.preview)
}

#Preview("Raw fallback") {
    SkillEditorView(
        agent: .claudeCode,
        skill: previewSkill(named: "commented-skill", content: """
        ---
        # kept by hand, do not reorder
        name: commented-skill
        metadata:
          type: reference
        ---

        Body text.
        """)
    )
    .environment(AgentHubViewModel.preview)
}
