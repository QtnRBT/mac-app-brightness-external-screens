import AppKit
import SwiftUI

/// The single "Réglages" window: `SettingsView` in a plain titled `NSWindow`
/// (the app has no SwiftUI scenes, see `ScreenBrightnessApp`).
///
/// While the window is open the app switches from `.accessory` to `.regular`,
/// like other menu bar apps' settings: the window then shows in ⌘-Tab, the
/// Dock and Mission Control, so it can be found again once another app
/// covers it, and the menu bar carries the app's menus (⌘W, ⌘Q…). The app
/// goes back to `.accessory` when the window closes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let launchAtLogin = LaunchAtLogin()
    private var window: NSWindow?

    /// Opens the window, or brings it to the front if already open.
    @objc func showWindow(_ sender: Any?) {
        let window = self.window ?? makeWindow()
        self.window = window
        reloadSystemState()

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        // The app is never active on its own (the panel does not activate
        // it), and the cooperative `NSApp.activate()` depends on the
        // frontmost app yielding: it leaves the window inactive behind
        // after a `--show-settings` launch. Opening settings is an explicit
        // user request, so take activation.
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(launchAtLogin: launchAtLogin))
        // The window takes the form's height; its width is fixed by the view.
        controller.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: controller)
        window.title = "Réglages de Screen Brightness"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.delegate = self
        // Size it now (the hosting controller would only after the first
        // layout) so it is centered right; then restore the last position.
        window.setContentSize(controller.view.fittingSize)
        window.center()
        window.setFrameAutosaveName("Settings")
        return window
    }

    /// The user may change these in System Settings while the window is
    /// open (Login Items, Accessibility): re-read them whenever it comes back.
    private func reloadSystemState() {
        launchAtLogin.reload()
        AccessibilityPermission.shared.refresh()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        reloadSystemState()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
