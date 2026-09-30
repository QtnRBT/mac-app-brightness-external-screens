import SwiftUI

/// "Général": launch at login.
struct GeneralSettingsSection: View {
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Section("Général") {
            Toggle("Ouvrir au démarrage", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ))
        }
    }
}
