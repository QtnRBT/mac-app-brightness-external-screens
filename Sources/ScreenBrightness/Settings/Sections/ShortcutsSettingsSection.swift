import SwiftUI

/// "Raccourcis clavier": one recorder per global shortcut, and a reset.
struct ShortcutsSettingsSection: View {
    private let store = ShortcutStore.shared

    var body: some View {
        Section {
            ForEach(ShortcutAction.allCases) { action in
                ShortcutRow(action: action)
            }
        } header: {
            Text("Raccourcis clavier")
        } footer: {
            VStack(alignment: .trailing, spacing: 10) {
                Text("Ils fonctionnent partout, sans autorisation supplémentaire. Maintenus, ceux de luminosité se répètent.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Rétablir par défaut") { store.resetToDefaults() }
                    .disabled(store.isDefault)
            }
        }
    }
}

/// An action's name, its recorder and, below the name, why its shortcut is
/// refused or may not work.
private struct ShortcutRow: View {
    let action: ShortcutAction
    private let store = ShortcutStore.shared
    private let session = ShortcutRecorderSession.shared

    var body: some View {
        LabeledContent {
            ShortcutRecorder(action: action)
        } label: {
            Text(action.title)
            if let note {
                Text(note)
            }
        }
    }

    private var note: String? {
        if let rejection = session.rejection, rejection.action == action {
            return rejection.message
        }
        guard let shortcut = store.shortcut(for: action), session.action != action else { return nil }
        if store.unavailable.contains(action) {
            return "Indisponible : déjà pris par une autre app."
        }
        if SystemShortcuts.isReservedBySystem(shortcut) {
            return "macOS utilise aussi ce raccourci et passe en premier."
        }
        return nil
    }
}
