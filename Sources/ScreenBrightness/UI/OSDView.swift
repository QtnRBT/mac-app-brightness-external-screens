import SwiftUI

/// State of the brightness on-screen display, driven by `OSDController`.
@MainActor
@Observable
final class OSDModel {
    /// Level shown by the bar, 0...1.
    var level: Double = 0
    var isVisible = false
}

enum OSDMetrics {
    static let width: CGFloat = 232
    static let height: CGFloat = 44
    /// Room around the capsule inside the window, for the glass's shadow.
    static let shadowInset: CGFloat = 16
    static let windowSize = CGSize(width: width + 2 * shadowInset, height: height + 2 * shadowInset)
}

/// Tahoe-style brightness HUD: a small glass capsule with a sun glyph and a
/// white level bar, like the system's own brightness indicator.
struct OSDView: View {
    let model: OSDModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 20)
            OSDLevelBar(level: model.level)
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .frame(width: OSDMetrics.width, height: OSDMetrics.height)
        .capsuleBackground()
        .scaleEffect(model.isVisible ? 1 : 0.92, anchor: .topTrailing)
        .opacity(model.isVisible ? 1 : 0)
        .padding(OSDMetrics.shadowInset)
        .accessibilityElement()
        .accessibilityLabel("Luminosité")
        .accessibilityValue("\(Int((model.level * 100).rounded())) %")
    }
}

/// Thin pill track with a white fill, in the Control Center slider style.
private struct OSDLevelBar: View {
    let level: Double
    @Environment(\.colorScheme) private var colorScheme

    private static let height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(level, 0), 1)
            // Keep a visible round cap at small non-zero levels.
            let fill = clamped > 0 ? max(proxy.size.width * clamped, Self.height) : 0
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: fill)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.2), radius: 0.5, y: 0.25)
            }
        }
        .frame(height: Self.height)
    }
}
