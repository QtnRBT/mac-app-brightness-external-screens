import AppKit

/// Owns the model and the menu bar item for the lifetime of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItemController = StatusItemController(controller: DisplayController())
        self.statusItemController = statusItemController

        // `open ScreenBrightness.app --args --show-panel`: opens the panel on
        // its own shortly after launch, for screenshots. Never passed in
        // normal use (Finder, login items).
        if ProcessInfo.processInfo.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                statusItemController.showPanel()
            }
        }
    }
}
