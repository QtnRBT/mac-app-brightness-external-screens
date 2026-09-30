import AppKit
import SwiftUI

/// Menu bar icon plus the transparent panel it opens. Replaces
/// `MenuBarExtra(.window)`, whose own window background would put the glass
/// modules inside a second translucent container.
@MainActor
final class StatusItemController: NSObject {
    /// Gap between the bottom of the menu bar and the first module.
    private static let menuBarGap: CGFloat = 6
    /// Minimum distance between a module and the screen edge.
    private static let screenMargin: CGFloat = 8

    private let controller: DisplayController
    private let statusItem: NSStatusItem
    private let panel = FloatingPanel()
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    init(controller: DisplayController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Luminosité des écrans")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    var isPanelShown: Bool { panel.isVisible }

    @objc private func statusItemClicked(_ sender: Any?) {
        if isPanelShown {
            closePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Showing / hiding

    func showPanel() {
        guard !isPanelShown else { return }

        // Pick up changes made with the monitors' own buttons.
        controller.refresh()

        // A fresh hierarchy per opening, like a menu: `onAppear` runs again and
        // the sliders' scroll-wheel monitors are torn down on close.
        let hostingView = PanelHostingView(rootView: MenuContentView(controller: controller))
        hostingView.onSizeChange = { [weak self] in self?.layoutPanel() }
        panel.contentView = hostingView
        layoutPanel()

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        installMonitors()
        setButtonHighlighted(true)
    }

    func closePanel() {
        guard isPanelShown else { return }
        removeMonitors()
        panel.orderOut(nil)
        panel.contentView = nil
        setButtonHighlighted(false)
    }

    private func setButtonHighlighted(_ highlighted: Bool) {
        guard let button = statusItem.button else { return }
        button.highlight(highlighted)
        // The button resets its highlight when mouse tracking ends, which can
        // happen after our action ran: re-apply on the next turn.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            button.highlight(self.isPanelShown)
        }
    }

    // MARK: - Layout

    /// Sizes the panel to its SwiftUI content and places it under the status
    /// item: modules right-aligned with the icon (Control Center's anchoring),
    /// clamped inside the screen, top kept just under the menu bar.
    private func layoutPanel() {
        guard let hostingView = panel.contentView else { return }
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let inset = ModuleMetrics.panelPadding
        guard let button = statusItem.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            panel.setContentSize(size)
            return
        }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let menuBarBottom = min(buttonFrame.minY, visible.maxY)

        var x = buttonFrame.maxX + inset - size.width
        let minX = screen.frame.minX + Self.screenMargin - inset
        let maxX = screen.frame.maxX - Self.screenMargin + inset - size.width
        x = min(max(x, minX), maxX)
        let top = menuBarBottom - Self.menuBarGap + inset

        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    // MARK: - Dismissal

    private func installMonitors() {
        removeMonitors()

        // Clicks in other apps (desktop, other windows, other menu bar items).
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.closePanel() }
            }
        ) {
            monitors.append(global)
        }

        // Esc while the panel is key.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            let windowNumber = event.windowNumber
            // Local monitors run on the main thread.
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, windowNumber == self.panel.windowNumber else { return false }
                self.closePanel()
                return true
            }
            return consumed ? nil : event
        }) {
            monitors.append(local)
        }

        // Cmd-Tab or any other app activation.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }
}
