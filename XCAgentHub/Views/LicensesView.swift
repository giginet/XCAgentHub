import SwiftUI

/// The Licenses window: the bundled open source dependencies on the left,
/// the selected one's license text on the right.
struct LicensesView: View {
    @State private var selection: ThirdPartyLicense.ID? = ThirdPartyLicense.all.first?.id

    var body: some View {
        NavigationSplitView {
            List(ThirdPartyLicense.all, selection: $selection) { license in
                // The VStack is load-bearing: a custom View struct as the row
                // root crashes macOS 27 beta's List (ViewListTree assertion);
                // wrapping it in a builtin container avoids it.
                VStack(alignment: .leading, spacing: 2) {
                    Text(license.name)
                        .font(.headline)
                    Text(license.repositoryPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(license.id)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            if let license = selected {
                detail(for: license)
            } else {
                ContentUnavailableView(
                    "Select a Dependency",
                    systemImage: "doc.text",
                    description: Text("Choose one of the bundled open source projects.")
                )
            }
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    private var selected: ThirdPartyLicense? {
        ThirdPartyLicense.all.first { $0.id == selection }
    }

    private func detail(for license: ThirdPartyLicense) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Link(license.repositoryURL.absoluteString, destination: license.repositoryURL)
                    .font(.callout)
                Text(license.text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .navigationTitle(license.name)
    }
}

extension LicensesView {
    static let windowID = "licenses"
}

#Preview {
    LicensesView()
}
