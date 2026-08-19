import SwiftUI

@main
struct XCAgentHubApp: App {
    @State private var model = AgentHubViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
