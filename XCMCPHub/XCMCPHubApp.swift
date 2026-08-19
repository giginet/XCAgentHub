import SwiftUI

@main
struct XCMCPHubApp: App {
    @State private var model = MCPHubViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
    }
}
