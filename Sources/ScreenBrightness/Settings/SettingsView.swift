import SwiftUI

/// The settings pane: a grouped form, like System Settings. Each section is
/// its own view (see `Sections/`), listed here in display order; adding a
/// section is one new file plus one line below.
struct SettingsView: View {
    static let width: CGFloat = 480

    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Form {
            GeneralSettingsSection(launchAtLogin: launchAtLogin)
            KeyboardSettingsSection()
            ShortcutsSettingsSection()
            AboutSettingsSection()
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Self.width)
    }
}
