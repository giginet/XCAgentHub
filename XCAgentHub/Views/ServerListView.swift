import SwiftUI

/// Lists the MCP servers configured for one agent, with add, edit, delete,
/// and enable/disable controls. Clicking a row selects it; double-clicking
/// (or right-click → Edit…) opens the edit sheet, and the trash button in
/// the bottom bar deletes the selection.
struct ServerListView: View {
    @Environment(AgentHubViewModel.self) private var model

    let agent: AgentKind

    @State private var selectedServerNames = Set<MCPServer.ID>()
    @State private var isAddingServer = false
    @State private var editingServer: MCPServer?
    @State private var serversPendingDeletion: [MCPServer] = []

    var body: some View {
        let servers = model.servers(for: agent)
        Group {
            if let error = model.loadError(for: agent) {
                ContentUnavailableView {
                    Label("Cannot Read Configuration", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        model.reload(agent)
                    }
                }
            } else if servers.isEmpty {
                ContentUnavailableView {
                    Label("No MCP Servers", systemImage: "server.rack")
                } description: {
                    if model.configFileExists(for: agent) {
                        Text("\(agent.displayName) has no MCP servers configured yet.")
                    } else {
                        Text("The configuration file \(agent.configFileRelativePath) does not exist yet. It will be created when you add a server.")
                    }
                } actions: {
                    Button("Add Server") {
                        isAddingServer = true
                    }
                }
            } else {
                serverList(servers)
            }
        }
        .navigationTitle(agent.displayName)
        .navigationSubtitle(agent.configFileRelativePath)
        .toolbar {
            ToolbarItem {
                Button("Show in Finder", systemImage: "finder") {
                    if let url = model.configFileURL(for: agent) {
                        FinderReveal.show(url)
                    }
                }
                .disabled(model.configFileURL(for: agent) == nil)
                .help("Show \(agent.configFileRelativePath) in Finder")
            }
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") {
                    model.reload(agent)
                }
                .help("Reload the configuration file from disk")
            }
            ToolbarItem {
                Button("Add Server", systemImage: "plus") {
                    isAddingServer = true
                }
                .help("Add a new MCP server")
            }
        }
        .sheet(isPresented: $isAddingServer) {
            ServerFormView(agent: agent, original: nil)
        }
        .sheet(item: $editingServer) { server in
            ServerFormView(agent: agent, original: server)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { !serversPendingDeletion.isEmpty },
                set: { if !$0 { serversPendingDeletion = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                for server in serversPendingDeletion {
                    model.delete(server, for: agent)
                }
                selectedServerNames.subtract(serversPendingDeletion.map(\.id))
                serversPendingDeletion = []
            }
        } message: {
            Text("Removed from \(agent.configFileRelativePath). A backup of the file is kept.")
        }
    }

    private func serverList(_ servers: [MCPServer]) -> some View {
        VStack(spacing: 0) {
            List(servers, selection: $selectedServerNames) { server in
                // The VStack is load-bearing: a custom View struct as the row
                // root crashes macOS 27 beta's List (ViewListTree assertion);
                // wrapping it in a builtin container avoids it.
                VStack {
                    ServerRowView(
                        server: server,
                        onToggle: { isEnabled in
                            model.setEnabled(isEnabled, serverNamed: server.name, for: agent)
                        }
                    )
                }
            }
            .contextMenu(forSelectionType: MCPServer.ID.self) { names in
                contextMenu(for: names)
            } primaryAction: { names in
                if let name = names.first {
                    editServer(named: name)
                }
            }

            Divider()
            bottomBar(serverCount: servers.count)
        }
    }

    @ViewBuilder
    private func contextMenu(for names: Set<MCPServer.ID>) -> some View {
        if let name = names.first {
            Button("Edit…") {
                editServer(named: name)
            }
        }
        if !names.isEmpty {
            Button("Delete…", role: .destructive) {
                serversPendingDeletion = servers(withIDs: names)
            }
        }
    }

    /// Trash button plus the server count, mirroring the bottom bar of a
    /// macOS list editor.
    private func bottomBar(serverCount: Int) -> some View {
        HStack {
            Button("Delete", systemImage: "trash") {
                serversPendingDeletion = servers(withIDs: selectedServerNames)
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .disabled(selectedServerNames.isEmpty)
            .help(selectedServerNames.isEmpty ? "Select a server to delete it" : "Delete the selected servers")
            Spacer()
            Text(serverCount == 1 ? "1 server" : "\(serverCount) servers")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var deletionTitle: String {
        if serversPendingDeletion.count == 1, let server = serversPendingDeletion.first {
            return "Delete \u{201C}\(server.name)\u{201D}?"
        }
        return "Delete \(serversPendingDeletion.count) servers?"
    }

    private func server(named name: String) -> MCPServer? {
        model.servers(for: agent).first { $0.name == name }
    }

    private func servers(withIDs ids: Set<MCPServer.ID>) -> [MCPServer] {
        model.servers(for: agent).filter { ids.contains($0.id) }
    }

    private func editServer(named name: String) {
        editingServer = server(named: name)
    }
}

/// A single row: enable toggle, name, and transport summary.
private struct ServerRowView: View {
    let server: MCPServer
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Enabled", isOn: Binding(get: { server.isEnabled }, set: onToggle))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help(server.isEnabled ? "Disable this server" : "Enable this server")
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.headline)
                    .foregroundStyle(server.isEnabled ? .primary : .secondary)
                Text(server.transport.summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(server.transport.isStdio ? "stdio" : "HTTP")
                .font(.caption2.smallCaps())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationSplitView {
        Text("Sidebar")
    } detail: {
        ServerListView(agent: .claudeCode)
    }
    .environment(AgentHubViewModel.preview)
    .frame(width: 720, height: 420)
}
