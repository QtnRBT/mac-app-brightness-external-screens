import Foundation
import Observation

/// The global shortcuts, kept in UserDefaults: one entry per action the user
/// changed, holding the shortcut or nothing (cleared). Actions without an
/// entry use their default, so resetting just removes the entries.
@MainActor
@Observable
final class ShortcutStore {
    static let shared = ShortcutStore()

    private(set) var shortcuts: [ShortcutAction: KeyboardShortcut] = [:]

    /// Actions whose hot key could not be registered (set by
    /// `ShortcutController`).
    var unavailable: Set<ShortcutAction> = []

    /// A recorder is capturing keys: hot keys are suspended meanwhile, so
    /// pressing an assigned shortcut records it instead of running it.
    var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            onChange?()
        }
    }

    /// Called after a shortcut changed or recording started / stopped.
    @ObservationIgnored var onChange: (() -> Void)?

    private init() {
        for action in ShortcutAction.allCases {
            shortcuts[action] = Self.load(action)
        }
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        shortcuts[action]
    }

    func setShortcut(_ shortcut: KeyboardShortcut?, for action: ShortcutAction) {
        guard shortcuts[action] != shortcut else { return }
        shortcuts[action] = shortcut
        let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        UserDefaults.standard.set(data, forKey: Self.defaultsKey(action))
        onChange?()
    }

    var isDefault: Bool {
        ShortcutAction.allCases.allSatisfy { shortcuts[$0] == $0.defaultShortcut }
    }

    func resetToDefaults() {
        guard !isDefault else { return }
        for action in ShortcutAction.allCases {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey(action))
            shortcuts[action] = action.defaultShortcut
        }
        onChange?()
    }

    /// Why `shortcut` cannot be given to `action`, or `nil` if it can.
    func conflict(for shortcut: KeyboardShortcut, action: ShortcutAction) -> String? {
        if !shortcut.isValidGlobalShortcut {
            return "Ajoutez ⌃ ou ⌘ à la combinaison."
        }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && shortcuts[$0] == shortcut }) {
            return "Déjà utilisé par « \(other.title) »."
        }
        if let title = SystemShortcuts.menuItemTitle(using: shortcut) {
            return "Déjà utilisé par le menu « \(title) »."
        }
        if SystemShortcuts.isReservedBySystem(shortcut) {
            return "Déjà utilisé par macOS (Réglages Système › Clavier › Raccourcis clavier)."
        }
        return nil
    }

    private static func defaultsKey(_ action: ShortcutAction) -> String {
        "shortcut.\(action.rawValue)"
    }

    /// Stored shortcut, `nil` if the user cleared it, the default if the
    /// user never changed it.
    private static func load(_ action: ShortcutAction) -> KeyboardShortcut? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(action)) else { return action.defaultShortcut }
        return try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
    }
}
