import Foundation
import Milepost

/// What the About window shows: the marketing version from the bundle plus
/// the revision the build came from. Milepost's build tool plugin records
/// the revision at build time, so it is absent only when the plugin has not
/// run.
enum AppVersion {
    static var name: String {
        bundleString("CFBundleName") ?? "AgentHub"
    }

    static var short: String {
        bundleString("CFBundleShortVersionString") ?? "—"
    }

    static var shortHash: String? {
        RevisionLoader.load()?.shortHash
    }

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}
