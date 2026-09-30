import AppKit

/// Owns the model and the menu bar item for the lifetime of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private let osd = OSDController()

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

        // `--show-osd`: shows the brightness HUD at 60 % on the pointer's
        // screen for 3 s, for screenshots.
        if ProcessInfo.processInfo.arguments.contains("--show-osd") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [osd] in
                let mouse = NSEvent.mouseLocation
                let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
                guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                else { return }
                osd.show(level: 0.6, on: number.uint32Value, holdFor: 3)
            }
        }
    }
}
