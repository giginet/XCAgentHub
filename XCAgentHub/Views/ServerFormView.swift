import SwiftUI

/// Sheet for adding a new MCP server or editing an existing one.
struct ServerFormView: View {
    private enum TransportKind: String, CaseIterable, Identifiable {
        case stdio
        case http

        var id: String { rawValue }

        var label: String {
            switch self {
            case .stdio: return "Standard I/O"
            case .http: return "HTTP"
            }
        }
    }

    /// One argument per table row. Rows need durable identity so edits keep
    /// row state while the text changes.
    private struct ArgumentRow: Identifiable {
        let id = UUID()
        var text: String
    }

    private struct EnvironmentRow: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    @Environment(AgentHubViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let agent: AgentKind
    let original: MCPServer?

    @State private var name: String
    @State private var transportKind: TransportKind
    @State private var command: String
    @State private var arguments: [ArgumentRow]
    @State private var environmentRows: [EnvironmentRow]
    @State private var url: String
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    init(agent: AgentKind, original: MCPServer?) {
        self.agent = agent
        self.original = original
        _name = State(initialValue: original?.name ?? "")
        switch original?.transport {
        case .stdio(let command, let args, let environment):
            _transportKind = State(initialValue: .stdio)
            _command = State(initialValue: command)
            _arguments = State(initialValue: args.map { ArgumentRow(text: $0) })
            _environmentRows = State(initialValue: environment
                .sorted { $0.key < $1.key }
                .map { EnvironmentRow(key: $0.key, value: $0.value) })
            _url = State(initialValue: "")
        case .http(let url):
            _transportKind = State(initialValue: .http)
            _command = State(initialValue: "")
            _arguments = State(initialValue: [])
            _environmentRows = State(initialValue: [])
            _url = State(initialValue: url)
        case nil:
            _transportKind = State(initialValue: .stdio)
            _command = State(initialValue: "")
            _arguments = State(initialValue: [])
            _environmentRows = State(initialValue: [])
            _url = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("my-mcp-server"))
                    Picker("Transport", selection: $transportKind) {
                        ForEach(TransportKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if transportKind == .stdio {
                    Section("Command") {
                        TextField("Command", text: $command, prompt: Text("/usr/bin/example"))
                            .font(.body.monospaced())
                    }
                    argumentsSection
                    environmentSection
                } else {
                    Section("Endpoint") {
                        TextField("URL", text: $url, prompt: Text("https://example.com/mcp"))
                            .font(.body.monospaced())
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if transportKind == .http {
                    Button("Test Connection") {
                        runConnectionTest()
                    }
                    .disabled(isTestingConnection || url.trimmingCharacters(in: .whitespaces).isEmpty)
                    if isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        connectionTestResultView
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add" : "Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(12)
        }
        .navigationTitle(original == nil ? "Add MCP Server" : "Edit MCP Server")
        .frame(width: 520, height: transportKind == .stdio ? 640 : 280)
        .onChange(of: url) {
            connectionTestResult = nil
        }
        .onChange(of: transportKind) {
            connectionTestResult = nil
        }
    }

    // MARK: - Connection test

    @ViewBuilder
    private var connectionTestResultView: some View {
        switch connectionTestResult {
        case .success(let detail):
            Label(detail, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(detail)
        case .failure(let detail):
            Label(detail, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(detail)
        case nil:
            EmptyView()
        }
    }

    private func runConnectionTest() {
        isTestingConnection = true
        connectionTestResult = nil
        let target = url.trimmingCharacters(in: .whitespaces)
        Task {
            connectionTestResult = await ConnectionTester.testHTTP(url: target)
            isTestingConnection = false
        }
    }

    // MARK: - Arguments table

    private var argumentsSection: some View {
        Section {
            Table(arguments) {
                TableColumn("Argument") { row in
                    TextField("Argument", text: argumentBinding(for: row.id), prompt: Text("argument"))
                        .font(.body.monospaced())
                        .labelsHidden()
                }
                TableColumn("") { row in
                    Button("Remove", systemImage: "minus.circle") {
                        arguments.removeAll { $0.id == row.id }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                }
                .width(24)
            }
            .frame(height: 150)
            Button("Add Argument", systemImage: "plus") {
                arguments.append(ArgumentRow(text: ""))
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Arguments")
        } footer: {
            Text("Pasting text with spaces inserts one row per word.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Table cells receive the row value, not a binding, so cell text fields
    /// bind back into `arguments` by row id. Writing whitespace-separated
    /// text (e.g. pasting "run --rm -i") expands it into one row per word.
    private func argumentBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let index = arguments.firstIndex(where: { $0.id == id }) else { return "" }
                return arguments[index].text
            },
            set: { newValue in
                guard let index = arguments.firstIndex(where: { $0.id == id }) else { return }
                arguments[index].text = newValue
                splitArgumentIfNeeded(rowID: id)
            }
        )
    }

    /// Pasting (or typing) whitespace-separated text into one row expands it
    /// into one row per word, keeping the first word in place.
    private func splitArgumentIfNeeded(rowID: UUID) {
        guard let index = arguments.firstIndex(where: { $0.id == rowID }) else { return }
        let parts = arguments[index].text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard parts.count > 1 else { return }
        arguments[index].text = parts[0]
        arguments.insert(
            contentsOf: parts.dropFirst().map { ArgumentRow(text: $0) },
            at: index + 1
        )
    }

    // MARK: - Environment table

    private var environmentSection: some View {
        Section("Environment") {
            Table(environmentRows) {
                TableColumn("Key") { row in
                    TextField("KEY", text: environmentBinding(for: row.id, \.key))
                        .font(.body.monospaced())
                        .labelsHidden()
                }
                .width(min: 120, ideal: 170)
                TableColumn("Value") { row in
                    TextField("value", text: environmentBinding(for: row.id, \.value))
                        .font(.body.monospaced())
                        .labelsHidden()
                }
                TableColumn("") { row in
                    Button("Remove", systemImage: "minus.circle") {
                        environmentRows.removeAll { $0.id == row.id }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                }
                .width(24)
            }
            .frame(height: 150)
            Button("Add Variable", systemImage: "plus") {
                environmentRows.append(EnvironmentRow(key: "", value: ""))
            }
            .buttonStyle(.borderless)
        }
    }

    /// Table cells receive the row value, not a binding, so cell text fields
    /// bind back into `environmentRows` by row id.
    private func environmentBinding(
        for id: UUID,
        _ keyPath: WritableKeyPath<EnvironmentRow, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let index = environmentRows.firstIndex(where: { $0.id == id }) else { return "" }
                return environmentRows[index][keyPath: keyPath]
            },
            set: { newValue in
                guard let index = environmentRows.firstIndex(where: { $0.id == id }) else { return }
                environmentRows[index][keyPath: keyPath] = newValue
            }
        )
    }

    // MARK: - Saving

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }
        switch transportKind {
        case .stdio:
            return !command.trimmingCharacters(in: .whitespaces).isEmpty
        case .http:
            return !url.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func save() {
        let transport: MCPServer.Transport
        switch transportKind {
        case .stdio:
            let args = arguments
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let environment = environmentRows.reduce(into: [String: String]()) { result, row in
                let key = row.key.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return }
                result[key] = row.value.trimmingCharacters(in: .whitespaces)
            }
            transport = .stdio(
                command: command.trimmingCharacters(in: .whitespaces),
                args: args,
                environment: environment
            )
        case .http:
            transport = .http(url: url.trimmingCharacters(in: .whitespaces))
        }
        let server = MCPServer(
            name: name.trimmingCharacters(in: .whitespaces),
            transport: transport,
            isEnabled: original?.isEnabled ?? true
        )
        model.upsert(server, replacing: original?.name, for: agent)
        dismiss()
    }
}

#Preview("Add") {
    ServerFormView(agent: .claudeCode, original: nil)
        .environment(AgentHubViewModel.preview)
}

#Preview("Edit HTTP") {
    ServerFormView(
        agent: .claudeCode,
        original: MCPServer(
            name: "safari-mcp",
            transport: .http(url: "https://example.com/mcp"),
            isEnabled: true
        )
    )
    .environment(AgentHubViewModel.preview)
}

#Preview("Edit") {
    ServerFormView(
        agent: .codex,
        original: MCPServer(
            name: "xcode-tools",
            transport: .stdio(
                command: "xcrun",
                args: ["mcpbridge", "--verbose", "--timeout", "30"],
                environment: ["MCP_XCODE_PID": "663", "MCP_XCODE_SESSION_ID": "989A29A4"]
            ),
            isEnabled: true
        )
    )
    .environment(AgentHubViewModel.preview)
}
