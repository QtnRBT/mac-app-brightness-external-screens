import AppKit

/// Keeps one system-wide hot key per assigned shortcut, re-registered
/// whenever the user changes them, and suspended while a recorder listens.
@MainActor
final class ShortcutController {
    private let store = ShortcutStore.shared
    private let hotKeys = HotKeyCenter()
    private let perform: (ShortcutAction) -> Void

    init(perform: @escaping (ShortcutAction) -> Void) {
        self.perform = perform
    }

    func start() {
        store.onChange = { [weak self] in self?.update() }
        update()
    }

    private func update() {
        hotKeys.unregisterAll()
        guard !store.isRecording else { return }
        var unavailable = Set<ShortcutAction>()
        for action in ShortcutAction.allCases {
            guard let shortcut = store.shortcut(for: action) else { continue }
            let status = hotKeys.register(shortcut, repeats: action.repeatsWhileHeld) { [weak self] in
                self?.perform(action)
            }
            if status != noErr { unavailable.insert(action) }
        }
        if store.unavailable != unavailable { store.unavailable = unavailable }
    }
}
