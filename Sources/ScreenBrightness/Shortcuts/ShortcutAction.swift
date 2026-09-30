import AppKit
import Carbon.HIToolbox

/// What a global keyboard shortcut can do, in the settings' display order.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case brightnessUp
    case brightnessDown
    case allScreensUp
    case allScreensDown
    case togglePanel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brightnessUp: "Augmenter la luminosité"
        case .brightnessDown: "Diminuer la luminosité"
        case .allScreensUp: "Augmenter tous les écrans"
        case .allScreensDown: "Diminuer tous les écrans"
        case .togglePanel: "Afficher le panneau"
        }
    }

    /// ⌃⌥↑/↓ for the pointer's screen, ⌃⌥⌘↑/↓ for all screens. Neither is
    /// a macOS shortcut (⌃↑/⌃↓ is Mission Control, and ⌃⌥⇧ + arrows is
    /// taken by the system too); the panel has none.
    var defaultShortcut: KeyboardShortcut? {
        switch self {
        case .brightnessUp: KeyboardShortcut(keyCode: kVK_UpArrow, modifiers: [.control, .option])
        case .brightnessDown: KeyboardShortcut(keyCode: kVK_DownArrow, modifiers: [.control, .option])
        case .allScreensUp: KeyboardShortcut(keyCode: kVK_UpArrow, modifiers: [.control, .option, .command])
        case .allScreensDown: KeyboardShortcut(keyCode: kVK_DownArrow, modifiers: [.control, .option, .command])
        case .togglePanel: nil
        }
    }

    /// Held down, the brightness actions keep stepping at the keyboard's
    /// repeat rate, like the brightness keys.
    var repeatsWhileHeld: Bool { self != .togglePanel }
}
