import AppKit

/// Plain AppKit entry point. The app has no windows of its own: only a menu
/// bar item and its transparent panel (see `StatusItemController`); SwiftUI
/// renders the panel's content. A SwiftUI `App` would need a scene, and even
/// an unused `Settings` scene leaves an invisible window on screen.
@main
enum ScreenBrightnessApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // `run()` never returns, so `delegate` stays alive.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
