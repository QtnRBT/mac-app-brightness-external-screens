import AppKit
import SwiftUI

/// Borderless, fully transparent, non-activating panel. It draws nothing
/// itself: the SwiftUI modules it hosts carry their own glass and shadows, so
/// they float directly over the desktop like Control Center's.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    // Key status lets the switch, buttons and Esc receive events without
    // activating the app (and stealing focus from the frontmost one).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Backdrop

    /// Control Center's blur under the modules, in a child window.
    private let backdrop = PanelBackdropWindow()

    /// Fades the backdrop in or out with the content. Show it once the panel
    /// is on screen.
    func setBackdropVisible(_ visible: Bool) {
        if visible {
            backdrop.show(under: self)
        } else {
            backdrop.hide()
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        backdrop.follow(self)
    }

    override func orderOut(_ sender: Any?) {
        backdrop.detach()
        super.orderOut(sender)
    }
}

/// Hosting view with a clear background that reports SwiftUI size changes
/// (e.g. a screen plugged in while the panel is open) so the panel can be
/// resized while staying anchored under the menu bar.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isOpaque: Bool { false }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard let onSizeChange else { return }
        // Defer: this can be called in the middle of a layout pass.
        DispatchQueue.main.async(execute: onSizeChange)
    }
}
