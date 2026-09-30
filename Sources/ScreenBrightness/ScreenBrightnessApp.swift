import SwiftUI

@main
struct ScreenBrightnessApp: App {
    // The menu bar item and its transparent panel are AppKit-driven (see
    // `StatusItemController`); SwiftUI only renders the panel's content.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // An App needs at least one scene; this one is never shown
        // (LSUIElement app, no main menu).
        Settings {
            EmptyView()
        }
    }
}
