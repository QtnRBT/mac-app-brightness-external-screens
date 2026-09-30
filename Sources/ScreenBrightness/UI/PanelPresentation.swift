import SwiftUI

/// Drives the panel's appear/disappear animation. The window itself is shown
/// at once and hidden only after the content has animated out, so the glass
/// modules grow out of (and shrink back into) the menu bar icon like Control
/// Center's.
@MainActor
@Observable
final class PanelPresentation {
    var isPresented = false
    /// Point the content scales from, in unit coordinates of the panel: the
    /// status item's position along the top edge.
    var anchor: UnitPoint = .top

    static let showAnimation = Animation.spring(duration: 0.32, bounce: 0.18)
    static let hideAnimation = Animation.easeIn(duration: 0.14)
}

extension View {
    /// Scale + fade + blur from the anchor, driven by `presentation`.
    func panelPresentation(_ presentation: PanelPresentation) -> some View {
        modifier(PanelPresentationModifier(presentation: presentation))
    }
}

private struct PanelPresentationModifier: ViewModifier {
    let presentation: PanelPresentation

    func body(content: Content) -> some View {
        let shown = presentation.isPresented
        content
            .scaleEffect(shown ? 1 : 0.86, anchor: presentation.anchor)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 6)
    }
}
