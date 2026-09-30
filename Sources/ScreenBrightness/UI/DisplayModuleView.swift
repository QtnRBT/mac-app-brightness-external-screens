import SwiftUI

/// One Control Center–style module for a single screen: bold title, subtle
/// percentage, and a sun / slider / sun row.
struct DisplayModuleView: View {
    let display: DisplayItem
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(display.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if display.isControllable {
                    Text("\(Int((display.brightness * 100).rounded())) %")
                        .font(.system(size: 11, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "sun.min.fill")
                    .font(.system(size: 11, weight: .regular))
                    .frame(width: 14)
                    .accessibilityHidden(true)
                BrightnessSlider(
                    value: display.brightness,
                    isEnabled: display.isControllable,
                    accessibilityLabel: "Luminosité de \(display.name)",
                    onChange: onChange
                )
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            .opacity(display.isControllable ? 1 : 0.5)

            if !display.isControllable {
                Text("DDC non supporté par cet écran")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, -2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, display.isControllable ? 7 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moduleBackground()
        .accessibilityElement(children: .contain)
    }
}
