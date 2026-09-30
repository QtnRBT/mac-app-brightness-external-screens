import SwiftUI

/// "Clavier": Accessibility status for the brightness keys, and the F1/F2
/// option.
struct KeyboardSettingsSection: View {
    private let access = AccessibilityPermission.shared
    @Bindable private var preferences = BrightnessKeyPreferences.shared

    var body: some View {
        Section {
            LabeledContent {
                if access.isTrusted {
                    Label {
                        Text("Autorisées")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button("Autoriser…") { access.request() }
                }
            } label: {
                Text("Touches de luminosité")
                Text(access.isTrusted
                     ? "Elles règlent l'écran sous le pointeur."
                     : "Elles ont besoin de l'accès Accessibilité.")
            }

            Toggle("Touches F1/F2 pour la luminosité", isOn: $preferences.functionKeysEnabled)
        } header: {
            Text("Clavier")
        } footer: {
            Text("Pour les claviers qui envoient F1/F2 au lieu des touches de luminosité. ⌘F1 etc. restent libres.")
                .foregroundStyle(.secondary)
        }
    }
}
