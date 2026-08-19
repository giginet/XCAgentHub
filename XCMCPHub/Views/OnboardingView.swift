import SwiftUI

/// Shown until the user grants sandbox access to the CodingAssistant folder.
struct OnboardingView: View {
    @Environment(MCPHubViewModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to XCMCPHub")
                .font(.title.bold())
            Text("XCMCPHub manages the MCP servers of the coding agents that run inside Xcode. To read and update their configuration files, grant access to the folder below.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Text(ConfigAccessManager.defaultFolderURL.path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Button("Grant Access…") {
                if model.access.promptForFolder() {
                    model.reloadAll()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingView()
        .environment(MCPHubViewModel.preview)
        .frame(width: 640, height: 420)
}
