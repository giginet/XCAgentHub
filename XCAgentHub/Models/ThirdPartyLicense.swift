import Foundation

/// One bundled open source dependency and the license text shipped with it.
/// The texts live in `Licenses/` and are copied verbatim from each project,
/// so they stay the notice the license itself requires.
struct ThirdPartyLicense: Identifiable, Sendable {
    var name: String
    var repositoryURL: URL
    /// Name of the bundled `.txt` holding the license, without its extension.
    var resourceName: String

    var id: String { name }

    /// "mattt/swift-toml" — enough to tell two projects of the same name apart.
    var repositoryPath: String {
        repositoryURL.path().trimmingPrefix("/").description
    }

    static let all: [ThirdPartyLicense] = [
        ThirdPartyLicense(
            name: "swift-toml",
            repositoryURL: URL(string: "https://github.com/mattt/swift-toml")!,
            resourceName: "swift-toml"
        ),
        ThirdPartyLicense(
            name: "Milepost",
            repositoryURL: URL(string: "https://github.com/giginet/Milepost")!,
            resourceName: "Milepost"
        ),
    ]

    /// The license text, or a note naming the resource that failed to load.
    var text: String {
        guard
            let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: "txt",
                subdirectory: "Licenses"
            ) ?? Bundle.main.url(forResource: resourceName, withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "The bundled license text \u{201C}\(resourceName).txt\u{201D} is missing. See \(repositoryURL.absoluteString)."
        }
        return text
    }
}
