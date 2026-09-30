import SwiftUI

/// Small Control Center–like controls under the modules. Pure: all actions
/// are injected, so it renders with fake state.
struct PanelFooterView: View {
    let isRefreshing: Bool
    @Binding var launchAtLogin: Bool
    @Binding var functionKeys: Bool
    /// Accessibility not granted yet: show the row that asks for it.
    let needsKeyAccess: Bool
    let onRequestKeyAccess: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if needsKeyAccess {
                keyAccessRow
            }

            VStack(spacing: 6) {
                switchRow("Ouvrir au démarrage", isOn: $launchAtLogin)
                switchRow("Touches F1/F2 pour la luminosité", isOn: $functionKeys)
                    .help("Pour les claviers qui envoient F1/F2 au lieu des touches de luminosité")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .moduleBackground(cornerRadius: 14)

            HStack(spacing: 8) {
                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 11, height: 11)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text("Rafraîchir")
                    }
                }
                .disabled(isRefreshing)
                .help("Relire la luminosité des écrans")

                Spacer()

                Button(action: onQuit) {
                    Text("Quitter")
                }
                .keyboardShortcut("q")
            }
            .footerButtonStyle()
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    /// Unobtrusive call to action: the brightness keys need Accessibility.
    private var keyAccessRow: some View {
        Button(action: onRequestKeyAccess) {
            HStack(spacing: 7) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Autoriser les touches de luminosité…")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    // One line, so the panel's measured height stays exact.
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .moduleBackground(cornerRadius: 14)
        .help("Les touches de luminosité du clavier ont besoin de l'accès Accessibilité (Réglages Système › Confidentialité et sécurité › Accessibilité)")
    }
}

private extension View {
    /// The system glass button on macOS 26+ (it gets Liquid Glass's press
    /// reaction for free, as Apple recommends over custom glass buttons);
    /// the hand-made capsule before.
    @ViewBuilder
    func footerButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
        } else {
            buttonStyle(CapsuleButtonStyle())
        }
    }
}

/// Small capsule button, like Control Center's "Modifier les commandes".
struct CapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .contentShape(Capsule())
            .capsuleBackground()
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.6))
    }
}
