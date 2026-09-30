import SwiftUI

/// Metrics shared by every Control Center–style module in the panel.
enum ModuleMetrics {
    static let cornerRadius: CGFloat = 20
    static let panelWidth: CGFloat = 300
    static let panelPadding: CGFloat = 12
    static let moduleSpacing: CGFloat = 10
}

extension View {
    /// Rounded translucent "module" background: Liquid Glass on macOS 26+,
    /// a regular material with a hairline edge on older systems.
    func moduleBackground(cornerRadius: CGFloat = ModuleMetrics.cornerRadius) -> some View {
        modifier(ModuleBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// Same treatment for capsule-shaped footer controls.
    func capsuleBackground() -> some View {
        modifier(ModuleBackground(shape: Capsule(style: .continuous)))
    }
}

private struct ModuleBackground<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.modifier(MaterialModuleBackground(shape: shape))
        }
    }
}

/// Pre-Tahoe fallback. Kept separate so it can be reasoned about on its own.
struct MaterialModuleBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: shape)
            .overlay(
                shape.strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55),
                    lineWidth: 0.5
                )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 1.5, y: 0.5)
    }
}
