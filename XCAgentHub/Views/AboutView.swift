import SwiftUI

/// The About window: app icon, version, and the revision the build came
/// from.
struct AboutView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 16) {
            appIcon
            VStack(spacing: 4) {
                Text(AppVersion.name)
                    .font(.title2.bold())
                Text("Manage the MCP servers and skills of the coding agents in Xcode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("Version", AppVersion.short)
                if let shortHash = AppVersion.shortHash {
                    row("Revision", shortHash, isMonospaced: true)
                }
            }

            Button("Open Source Licenses…") {
                openWindow(id: LicensesView.windowID)
            }
            .buttonStyle(.link)
        }
        .padding(24)
        .frame(width: 340)
    }

    private var appIcon: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: 96, height: 96)
    }

    private func row(_ label: String, _ value: String, isMonospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(isMonospaced ? .body.monospaced() : .body)
                .textSelection(.enabled)
        }
    }
}

extension AboutView {
    static let windowID = "about"
}

#Preview {
    AboutView()
}
