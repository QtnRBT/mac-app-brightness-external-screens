import AppKit
import SwiftUI

/// Shows the brightness HUD on a given screen, near its top-right corner
/// just under the menu bar (where macOS 26 shows its own). Presses in quick
/// succession only move the bar and push back the fade-out, so the HUD never
/// blinks. Drawn by the app itself: no private OSD framework.
@MainActor
final class OSDController {
    /// How long the HUD stays after the last update.
    nonisolated static let defaultHoldDuration: TimeInterval = 1.5
    /// Gap between the bottom of the menu bar and the capsule.
    private static let menuBarGap: CGFloat = 6
    /// Distance between the capsule and the screen's right edge.
    private static let screenMargin: CGFloat = 8

    private static let showAnimation = Animation.spring(duration: 0.28, bounce: 0.15)
    private static let hideAnimation = Animation.easeIn(duration: 0.3)
    private static let levelAnimation = Animation.smooth(duration: 0.14)

    private let model = OSDModel()
    private lazy var panel = makePanel()
    private var hideWorkItem: DispatchWorkItem?

    /// Shows (or updates) the HUD with `level` (0...1) on the screen whose
    /// display ID is `displayID`.
    func show(level: Double, on displayID: CGDirectDisplayID, holdFor duration: TimeInterval = defaultHoldDuration) {
        guard let screen = NSScreen.screens.first(where: { Self.displayID(of: $0) == displayID }) else { return }
        let frame = Self.frame(on: screen)
        if panel.isVisible {
            // On screen, possibly fading out: move the bar and, if needed,
            // bring the capsule back from wherever the fade-out is.
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            withAnimation(Self.levelAnimation) { model.level = level }
            if !model.isVisible {
                withAnimation(Self.showAnimation) { model.isVisible = true }
            }
        } else {
            // Start hidden at the new level, then animate in on the next turn
            // so the hidden state is rendered once first.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.isVisible = false
                model.level = level
            }
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            DispatchQueue.main.async { [model] in
                withAnimation(Self.showAnimation) { model.isVisible = true }
            }
        }

        scheduleHide(after: duration)
    }

    private func scheduleHide(after duration: TimeInterval) {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func hide() {
        hideWorkItem = nil
        withAnimation(Self.hideAnimation, completionCriteria: .logicallyComplete) {
            model.isVisible = false
        } completion: { [weak self] in
            // Shown again meanwhile: keep the window.
            guard let self, !self.model.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: - Window

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: OSDMetrics.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: OSDView(model: model))
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
        return panel
    }

    /// Window frame (including the shadow inset) so the capsule sits right
    /// under the menu bar, against the right edge.
    private static func frame(on screen: NSScreen) -> NSRect {
        let size = OSDMetrics.windowSize
        let inset = OSDMetrics.shadowInset
        let top = screen.visibleFrame.maxY - menuBarGap + inset
        let right = screen.frame.maxX - screenMargin + inset
        return NSRect(x: right - size.width, y: top - size.height, width: size.width, height: size.height)
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
