import AppKit
import SwiftUI

/// Control Center's backdrop: under the whole group of glass modules, what is
/// behind the panel (desktop, other windows) is blurred and slightly dimmed,
/// and the effect fades out softly around the group, with no visible edge.
///
/// The SwiftUI side only leaves room for the soft edge (`panelBackdrop()`);
/// the blur itself is a `PanelBackdropWindow` that `FloatingPanel` keeps
/// right under the panel.
enum PanelBackdrop {
    /// Room left around the content (sides and bottom) for the feathered
    /// edge. The panel window grows by this much, so its placement has to
    /// account for it (see `StatusItemController.layoutPanel`).
    static let margin: CGFloat = 28
    /// Width of the soft edge, as a Gaussian standard deviation in points.
    static let featherSigma: CGFloat = 10

    static var contentInsets: EdgeInsets {
        // No top margin: the panel already starts inside the menu bar.
        EdgeInsets(top: 0, leading: margin, bottom: margin, trailing: margin)
    }
}

extension View {
    /// Leaves room around the panel's content for the backdrop's feathered
    /// edge.
    func panelBackdrop() -> some View {
        padding(PanelBackdrop.contentInsets)
    }
}

/// Borderless, click-through child window holding the feathered blur, kept
/// exactly under its parent panel and faded with the panel's presentation.
///
/// Why a window of its own, and not a view in the panel (as observed on
/// macOS 27):
/// - a behind-window visual effect view stops blurring once it is drawn below
///   full opacity, so it can't follow the panel's fade; fading a whole window
///   is what menus do, and works;
/// - an AppKit view hosted in the panel's SwiftUI hierarchy keeps the
///   presented content from appearing;
/// - it ignores the mouse, so clicks between and around the modules still go
///   through to what is below, which dismisses the panel as before.
final class PanelBackdropWindow: NSWindow {
    private weak var parentPanel: NSWindow?

    init() {
        super.init(
            // Placeholder size: the frame follows the panel's.
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        contentView = FeatheredBlurView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Fades in under `panel`, which must be on screen: a child added to a
    /// window that is not ordered in yet ends up above it.
    func show(under panel: NSWindow) {
        // With Reduce Transparency the modules are opaque: nothing shows
        // through them, so there is nothing to blur.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return }
        if parentPanel !== panel {
            detach()
            level = panel.level
            alphaValue = 0
            setFrame(panel.frame, display: false)
            panel.addChildWindow(self, ordered: .below)
            parentPanel = panel
        }
        // As long as the presentation's spring (see `PanelPresentation`).
        fade(to: 1, duration: 0.3, timing: .easeOut)
    }

    /// Fades out with the content (the presentation's exact ease-in).
    func hide() {
        guard parentPanel != nil else { return }
        fade(to: 0, duration: 0.14, timing: .easeIn)
    }

    /// Follows the panel's frame: a child window follows its parent's moves,
    /// not its resizes.
    func follow(_ panel: NSWindow) {
        guard parentPanel === panel, frame != panel.frame else { return }
        setFrame(panel.frame, display: true)
    }

    /// Removes it at once (the panel is being ordered out).
    func detach() {
        guard let parentPanel else { return }
        parentPanel.removeChildWindow(self)
        orderOut(nil)
        alphaValue = 0
        self.parentPanel = nil
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, timing: CAMediaTimingFunctionName) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            animator().alphaValue = alpha
        }
    }
}

/// Behind-window blur masked by a feathered rounded rectangle: fully opaque
/// under the content, fading to nothing at the sides and bottom, and fading
/// in from the top edge down to the first module.
final class FeatheredBlurView: NSVisualEffectView {
    private var maskKey: (size: CGSize, scale: CGFloat)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        blendingMode = .behindWindow
        // Blurs and slightly dims in dark mode, frosts in light mode, like
        // Control Center's backdrop (and adapts on older systems too, unlike
        // `.hudWindow`, always dark there).
        material = .fullScreenUI
        // The panel never makes the app active; keep the blur live anyway.
        state = .active
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // The window's content view: resized by the window, without a layout pass.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMask()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateMask()
    }

    private func updateMask() {
        let size = bounds.size
        let scale = window?.backingScaleFactor ?? 2
        guard size.width > 0, size.height > 0 else { return }
        if let maskKey, maskKey.size == size, maskKey.scale == scale { return }
        maskKey = (size, scale)
        maskImage = Self.featheredMask(size: size, scale: scale).map { NSImage(cgImage: $0, size: size) }
    }

    /// Alpha mask at the screen's resolution (a mask image is applied pixel
    /// for pixel, not stretched to the view). Drawn in pixels, without a
    /// scaled context, so the shadow used as a Gaussian blur has exactly the
    /// intended size.
    private static func featheredMask(size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let margin = PanelBackdrop.margin * scale
        let sigma = PanelBackdrop.featherSigma * scale
        let radius = (ModuleMetrics.cornerRadius + ModuleMetrics.panelPadding) * scale
        let w = CGFloat(width), h = CGFloat(height)

        // The content's rectangle (origin bottom-left), extended past the top
        // edge so that edge is only shaped by the fade below.
        let core = CGRect(x: margin, y: margin, width: w - 2 * margin, height: h - margin + radius)
        // Draw it off to the left and let only its shadow land in the image:
        // a shadow's blur is Gaussian, with a standard deviation of about
        // half the blur value.
        let offset = w + 4 * sigma
        context.setShadow(offset: CGSize(width: offset, height: 0), blur: 2 * sigma, color: CGColor(gray: 0, alpha: 1))
        context.addPath(CGPath(roundedRect: core.offsetBy(dx: -offset, dy: 0), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        // Top: ease in from transparent at the panel's edge (inside the menu
        // bar) to opaque at the first module.
        let fade = ModuleMetrics.panelPadding * scale
        let colors = [0, 0.1, 0.35, 1].map { CGColor(gray: 0, alpha: $0) } as CFArray
        if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 0.4, 0.7, 1]) {
            context.setBlendMode(.destinationIn)
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: h),
                end: CGPoint(x: 0, y: h - fade),
                options: [.drawsAfterEndLocation]
            )
        }
        return context.makeImage()
    }
}
