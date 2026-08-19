import SwiftUI

/// The structured SKILL.md editor shared by the create and edit sheets:
/// dedicated fields for name, description and allowed-tools, a key/value
/// table for any other frontmatter, and the Markdown body below.
struct SkillFormView: View {
    @Binding var draft: SkillDraft
    /// Explains where the file lives; differs between creating and editing.
    let nameFooter: Text

    var body: some View {
        Form {
            identitySection
            allowedToolsSection
            additionalFieldsSection
            Section("Instructions") {
                TextEditor(text: $draft.instructions)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Frontmatter sections

    private var identitySection: some View {
        Section {
            TextField("Name", text: $draft.name, prompt: Text("my-skill"))
                .font(.body.monospaced())
            TextField(
                "Description",
                text: $draft.summary,
                prompt: Text("What this skill does and when to use it"),
                axis: .vertical
            )
            .lineLimit(2...4)
        } header: {
            Text("Frontmatter")
        } footer: {
            nameFooter
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var allowedToolsSection: some View {
        Section {
            Table(draft.toolRows) {
                TableColumn("Tool") { row in
                    TextField("Tool", text: toolBinding(for: row.id), prompt: Text("Bash"))
                        .font(.body.monospaced())
                        .labelsHidden()
                }
                TableColumn("") { row in
                    Button("Remove", systemImage: "minus.circle") {
                        draft.toolRows.removeAll { $0.id == row.id }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                }
                .width(24)
            }
            .frame(height: 76)
            Button("Add Tool", systemImage: "plus") {
                draft.toolRows.append(SkillDraft.ToolRow(name: ""))
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Allowed Tools")
        } footer: {
            Text("Written as a comma-separated \(SkillFrontmatter.allowedToolsKey) list. Leave empty to allow every tool.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var additionalFieldsSection: some View {
        Section {
            Table(draft.fieldRows) {
                TableColumn("Key") { row in
                    TextField("Key", text: fieldBinding(for: row.id, \.key), prompt: Text("license"))
                        .font(.body.monospaced())
                        .labelsHidden()
                }
                .width(min: 120, ideal: 170)
                TableColumn("Value") { row in
                    TextField("Value", text: fieldBinding(for: row.id, \.value), prompt: Text("MIT"))
                        .font(.body.monospaced())
                        .labelsHidden()
                }
                TableColumn("") { row in
                    Button("Remove", systemImage: "minus.circle") {
                        draft.fieldRows.removeAll { $0.id == row.id }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                }
                .width(24)
            }
            .frame(height: 76)
            Button("Add Field", systemImage: "plus") {
                draft.fieldRows.append(SkillDraft.FieldRow(key: "", value: ""))
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Additional Frontmatter")
        } footer: {
            Text("Blank keys are skipped, as are duplicates of the fields above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row bindings

    /// Table cells receive the row value, not a binding, so cell text fields
    /// bind back into the row arrays by row id.
    private func toolBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draft.toolRows.first { $0.id == id }?.name ?? "" },
            set: { newValue in
                guard let index = draft.toolRows.firstIndex(where: { $0.id == id }) else { return }
                draft.toolRows[index].name = newValue
            }
        )
    }

    private func fieldBinding(
        for id: UUID,
        _ keyPath: WritableKeyPath<SkillDraft.FieldRow, String>
    ) -> Binding<String> {
        Binding(
            get: { draft.fieldRows.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = draft.fieldRows.firstIndex(where: { $0.id == id }) else { return }
                draft.fieldRows[index][keyPath: keyPath] = newValue
            }
        )
    }
}

#Preview {
    @Previewable @State var draft = SkillDraft(
        frontmatter: SkillFrontmatter(
            name: "compose-app-icon",
            summary: "Author and validate Apple Icon Composer .icon packages",
            allowedTools: ["Bash", "Read"],
            extraFields: [(key: "license", value: "MIT")]
        ),
        body: "# compose-app-icon\n\nStart from the bundled JSON Schema."
    )
    SkillFormView(draft: $draft, nameFooter: Text("Stored in ClaudeAgentConfig/skills/compose-app-icon/SKILL.md"))
        .frame(width: 620, height: 640)
}
