import SwiftUI

/// Sheet for creating a new skill. The YAML frontmatter is composed with a
/// form — name, description, and allowed-tools have dedicated fields, and
/// any other key is added as a key/value row — while the Markdown body is
/// typed underneath.
struct SkillCreatorView: View {
    /// Rows need durable identity so a cell keeps focus while its text
    /// changes.
    private struct ToolRow: Identifiable {
        let id = UUID()
        var name: String
    }

    private struct FieldRow: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    @Environment(AgentHubViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let agent: AgentKind

    @State private var name = ""
    @State private var summary = ""
    /// Both tables start with one blank row so there is somewhere to type
    /// without hitting Add first. Blank rows are dropped when saving.
    @State private var toolRows: [ToolRow] = [ToolRow(name: "")]
    @State private var fieldRows: [FieldRow] = [FieldRow(key: "", value: "")]
    @State private var instructions = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                identitySection
                allowedToolsSection
                additionalFieldsSection
                Section("Instructions") {
                    TextEditor(text: $instructions)
                        .font(.body.monospaced())
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                }
            }
            .formStyle(.grouped)

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
        SkillStore.sanitizeDirectoryName(name)
    }

    // MARK: - Frontmatter sections

    private var identitySection: some View {
        Section {
            TextField("Name", text: $name, prompt: Text("my-skill"))
                .font(.body.monospaced())
            TextField(
                "Description",
                text: $summary,
                prompt: Text("What this skill does and when to use it"),
                axis: .vertical
            )
            .lineLimit(2...4)
        } header: {
            Text("Frontmatter")
        } footer: {
            Text("Created as \(agent.skillsDirectoryRelativePath)/\(directoryName.isEmpty ? "…" : directoryName)/SKILL.md. Agents match the description against the task at hand, so say when the skill applies.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var allowedToolsSection: some View {
        Section {
            Table(toolRows) {
                TableColumn("Tool") { row in
                    TextField("Tool", text: toolBinding(for: row.id), prompt: Text("Bash"))
                        .font(.body.monospaced())
                        .labelsHidden()
                }
                TableColumn("") { row in
                    Button("Remove", systemImage: "minus.circle") {
                        toolRows.removeAll { $0.id == row.id }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                }
                .width(24)
            }
            .frame(height: 76)
            Button("Add Tool", systemImage: "plus") {
                toolRows.append(ToolRow(name: ""))
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
            Table(fieldRows) {
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
                        fieldRows.removeAll { $0.id == row.id }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                }
                .width(24)
            }
            .frame(height: 76)
            Button("Add Field", systemImage: "plus") {
                fieldRows.append(FieldRow(key: "", value: ""))
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
            get: { toolRows.first { $0.id == id }?.name ?? "" },
            set: { newValue in
                guard let index = toolRows.firstIndex(where: { $0.id == id }) else { return }
                toolRows[index].name = newValue
            }
        )
    }

    private func fieldBinding(for id: UUID, _ keyPath: WritableKeyPath<FieldRow, String>) -> Binding<String> {
        Binding(
            get: { fieldRows.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = fieldRows.firstIndex(where: { $0.id == id }) else { return }
                fieldRows[index][keyPath: keyPath] = newValue
            }
        )
    }

    // MARK: - Saving

    private func save() {
        let frontmatter = SkillFrontmatter(
            name: directoryName,
            summary: summary,
            allowedTools: toolRows.map(\.name),
            extraFields: fieldRows.map { (key: $0.key, value: $0.value) }
        )
        let content = "\(frontmatter.rendered())\n\n\(instructions)"
        do {
            try model.createSkill(named: name, content: content, for: agent)
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

#Preview("Gemini") {
    SkillCreatorView(agent: .gemini)
        .environment(AgentHubViewModel.preview)
}
