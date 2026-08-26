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
                    // Wrap at a readable measure and grow downwards; without
                    // this the sentence is clipped in any language that needs
                    // more room than English.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280)
                // Said in the app itself, not only on the store page: this is
                // an independent tool, and Xcode is Apple's.
                Text("An independent tool, not affiliated with Apple. Xcode is a trademark of Apple Inc.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280)
                    .padding(.top, 4)
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
        // A minimum rather than a fixed width, then sized to fit: the window
        // stays compact but grows to whatever the translated labels need,
        // instead of truncating them.
        .frame(minWidth: 340)
        .fixedSize()
    }

    private var appIcon: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: 96, height: 96)
    }

    private func row(_ label: LocalizedStringKey, _ value: String, isMonospaced: Bool = false) -> some View {
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
