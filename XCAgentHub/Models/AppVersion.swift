import Foundation
import Milepost

/// What the About window shows: the marketing version and build number from
/// the bundle, plus the commit the build came from. Milepost's build tool
/// plugin records the revision at build time, so it is absent only when the
/// plugin has not run.
enum AppVersion {
    static var name: String {
        bundleString("CFBundleName") ?? "XCAgentHub"
    }

    static var short: String {
        bundleString("CFBundleShortVersionString") ?? "—"
    }

    static var build: String {
        bundleString("CFBundleVersion") ?? "—"
    }

    static var shortHash: String? {
        RevisionLoader.load()?.shortHash
    }

    static var branch: String? {
        RevisionLoader.load()?.branch
    }

    /// "1.0 (12)" — or with the commit appended when it is known.
    static var summary: String {
        guard let shortHash else { return "\(short) (\(build))" }
        return "\(short) (\(build)) · \(shortHash)"
    }

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}
