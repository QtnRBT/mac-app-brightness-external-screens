import SwiftUI

/// "À propos": the app version, from the bundle's Info.plist.
struct AboutSettingsSection: View {
    var body: some View {
        Section("À propos") {
            LabeledContent("Version", value: Self.version)
        }
    }

    /// "1.2.0 (42)", or "développement" when run outside the app bundle
    /// (`swift run`).
    private static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "développement" }
        guard let build = info?["CFBundleVersion"] as? String, build != short else { return short }
        return "\(short) (\(build))"
    }
}
