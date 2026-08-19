import SwiftUI

@main
struct XCAgentHubApp: App {
    @State private var model = AgentHubViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .commands {
            AboutCommands()
        }

        Window("About \(AppVersion.name)", id: AboutView.windowID) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Open Source Licenses", id: LicensesView.windowID) {
            LicensesView()
        }
        .restorationBehavior(.disabled)
    }
}

/// Replaces the standard About item so it opens this app's own window, and
/// puts the license list next to it.
private struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppVersion.name)") {
                openWindow(id: AboutView.windowID)
            }
            Button("Open Source Licenses…") {
                openWindow(id: LicensesView.windowID)
            }
        }
    }
}
