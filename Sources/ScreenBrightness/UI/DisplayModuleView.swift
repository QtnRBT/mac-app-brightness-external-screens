import SwiftUI

/// One Control Center–style module for a single screen.
struct DisplayModuleView: View {
    let display: DisplayItem
    let onChange: (Double) -> Void

    var body: some View {
        BrightnessModuleView(
            title: display.name,
            brightness: display.brightness,
            isEnabled: display.isControllable,
            caption: caption,
            accessibilityLabel: "Luminosité de \(display.name)",
            onChange: onChange
        )
    }

    /// Small secondary line under the slider, only when there is something
    /// the user should know.
    private var caption: String? {
        switch display.backend {
        case .unsupported: "DDC non supporté par cet écran"
        case .software: "Atténuation logicielle"
        case .builtIn, .ddc: nil
        }
    }
}

/// Control Center–style brightness module: bold title, subtle percentage,
/// and a sun / slider / sun row. Used per screen and for "all screens".
struct BrightnessModuleView: View {
    let title: String
    let brightness: Double
    let isEnabled: Bool
    let caption: String?
    let accessibilityLabel: String
    let onChange: (Double) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isEnabled {
                    Text("\(Int((brightness * 100).rounded())) %")
                        .font(.system(size: 11, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min.fill")
                    .font(.system(size: 11, weight: .regular))
                    .frame(width: 14)
                    .accessibilityHidden(true)
                BrightnessSlider(
                    value: brightness,
                    isEnabled: isEnabled,
                    showsKnob: isHovering,
                    accessibilityLabel: accessibilityLabel,
                    onChange: onChange
                )
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            .opacity(isEnabled ? 1 : 0.5)

            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, -2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, caption == nil ? 10 : 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moduleBackground()
        .contentShape(RoundedRectangle(cornerRadius: ModuleMetrics.cornerRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
    }

}
