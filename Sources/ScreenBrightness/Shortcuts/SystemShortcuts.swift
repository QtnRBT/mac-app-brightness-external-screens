import AppKit
import Carbon.HIToolbox

/// Shortcuts already taken elsewhere, which a global shortcut must not use.
@MainActor
enum SystemShortcuts {
    /// Whether macOS itself uses `shortcut` (Mission Control, Spaces,
    /// window tiling, screenshots… as enabled in System Settings ›
    /// Keyboard › Keyboard Shortcuts). The system handles those before any
    /// app, so a hot key on them would never fire.
    static func isReservedBySystem(_ shortcut: KeyboardShortcut) -> Bool {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
              let entries = array?.takeRetainedValue() as? [[String: Any]] else { return false }
        // Entries also carry the Fn bit for arrow and function keys: compare
        // the four modifiers a shortcut can hold.
        let mask = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        return entries.contains { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int else { return false }
            return UInt32(code) == shortcut.keyCode && UInt32(modifiers) & mask == shortcut.carbonModifiers
        }
    }

    /// Title of the app's own menu item with this key equivalent (⌘, ⌘W…),
    /// which a global hot key would otherwise shadow.
    static func menuItemTitle(using shortcut: KeyboardShortcut) -> String? {
        guard let character = KeyboardShortcut.character(for: shortcut.keyCode)?.lowercased() else { return nil }
        func search(_ menu: NSMenu) -> String? {
            for item in menu.items {
                if let submenu = item.submenu, let title = search(submenu) { return title }
                guard !item.keyEquivalent.isEmpty else { continue }
                // An uppercase key equivalent implies ⇧.
                var modifiers = item.keyEquivalentModifierMask.intersection(KeyboardShortcut.relevantModifiers)
                if item.keyEquivalent != item.keyEquivalent.lowercased() { modifiers.insert(.shift) }
                if item.keyEquivalent.lowercased() == character, modifiers == shortcut.modifiers { return item.title }
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(search)
    }
}
