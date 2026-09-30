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
    private let presentation = PanelPresentation()
    private var isClosing = false
    /// When a click outside last dismissed the panel. The menu bar item is
    /// drawn by the system, so clicking it to close first reaches our global
    /// monitor (mouse down) and only then the item's action (mouse up).
    private var lastOutsideDismissal: Date?
    private var anchor: Anchor?
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

    var isPanelShown: Bool { panel.isVisible && !isClosing }

    @objc private func statusItemClicked(_ sender: Any?) {
        if let dismissal = lastOutsideDismissal, Date().timeIntervalSince(dismissal) < 0.5 {
            // This click already closed the panel via the global monitor.
            lastOutsideDismissal = nil
            return
        }
        if isPanelShown {
            closePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Showing / hiding

    func showPanel() {
        guard !isPanelShown else { return }
        if isClosing {
            // Re-opened mid-close: animate back in from the current state.
            isClosing = false
            installMonitors()
            setButtonHighlighted(true)
            withAnimation(PanelPresentation.showAnimation) { presentation.isPresented = true }
            return
        }

        // Pick up changes made with the monitors' own buttons.
        controller.refresh()

        // A fresh hierarchy per opening, like a menu: `onAppear` runs again and
        // the sliders' scroll-wheel monitors are torn down on close.
        presentation.isPresented = false
        let hostingView = PanelHostingView(rootView: MenuContentView(controller: controller, presentation: presentation))
        hostingView.onSizeChange = { [weak self] in self?.layoutPanel() }
        panel.contentView = hostingView
        anchor = Self.findAnchor(statusItem: statusItem, excluding: panel)
        layoutPanel()

        panel.makeKeyAndOrderFront(nil)
        // Next turn, so the hidden state is rendered once before animating.
        DispatchQueue.main.async { [presentation] in
            withAnimation(PanelPresentation.showAnimation) { presentation.isPresented = true }
        }

        installMonitors()
        setButtonHighlighted(true)
    }

    func closePanel() {
        guard isPanelShown else { return }
        isClosing = true
        removeMonitors()
        setButtonHighlighted(false)
        withAnimation(PanelPresentation.hideAnimation, completionCriteria: .logicallyComplete) {
            presentation.isPresented = false
        } completion: { [weak self] in
            guard let self, self.isClosing else { return } // re-opened meanwhile
            self.isClosing = false
            self.panel.orderOut(nil)
            self.panel.contentView = nil
        }
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
        guard let hostingView = panel.contentView, let anchor else { return }
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let inset = ModuleMetrics.panelPadding
        let screenFrame = anchor.screen.frame
        let menuBarBottom = min(anchor.itemFrame.minY, anchor.screen.visibleFrame.maxY)

        var x = anchor.itemFrame.maxX + inset - size.width
        let minX = screenFrame.minX + Self.screenMargin - inset
        let maxX = screenFrame.maxX - Self.screenMargin + inset - size.width
        x = min(max(x, minX), maxX)
        let top = menuBarBottom - Self.menuBarGap + inset

        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        let iconX = (anchor.itemFrame.midX - x) / size.width
        presentation.anchor = UnitPoint(x: min(max(iconX, 0), 1), y: 0)
    }

    /// Frame (screen coordinates) of the menu bar item the panel hangs from,
    /// and its screen. With "displays have separate Spaces", the item is
    /// replicated in every screen's menu bar, each copy in its own window:
    /// use the copy that was clicked, otherwise the one on the screen with the
    /// pointer, otherwise the one on the main menu bar.
    /// Copies parked off-screen (hidden menu bars) are ignored.
    private static func findAnchor(statusItem: NSStatusItem, excluding panel: NSWindow) -> Anchor? {
        func anchor(for window: NSWindow?) -> Anchor? {
            guard let window, window !== panel else { return nil }
            let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) else { return nil }
            return Anchor(itemFrame: window.frame, screen: screen)
        }

        if let event = NSApp.currentEvent,
           [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(event.type),
           let clicked = anchor(for: event.window) {
            return clicked
        }

        // Besides the panel, the app's only windows are the item's copies.
        let itemWindows = NSApp.windows.filter { $0 !== panel && $0.frame.height < 60 }
        let candidates = ([statusItem.button?.window] + itemWindows).compactMap(anchor(for:))
        let mouse = NSEvent.mouseLocation
        if let best = candidates.first(where: { $0.screen.frame.contains(mouse) })
            ?? candidates.first(where: { $0.screen == NSScreen.screens.first })
            ?? candidates.first {
            return best
        }

        // Item not laid out (e.g. menu bar hidden): top-right of the main screen.
        guard let screen = NSScreen.screens.first else { return nil }
        let visible = screen.visibleFrame
        return Anchor(itemFrame: NSRect(x: visible.maxX, y: visible.maxY, width: 0, height: 0), screen: screen)
    }

    private struct Anchor {
        let itemFrame: NSRect
        let screen: NSScreen
    }

    // MARK: - Dismissal

    private func installMonitors() {
        removeMonitors()

        // Clicks in other apps (desktop, other windows, other menu bar items).
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.lastOutsideDismissal = Date()
                    self?.closePanel()
                }
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
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
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

