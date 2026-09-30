import AppKit
import SwiftUI

/// Control Center–style brightness slider.
///
/// On macOS 26+ this is the system `Slider`: white fill and white pill knob
/// that turns into a Liquid Glass lens while it is dragged, exactly like
/// Control Center's own sliders ("For controls like sliders and toggles, the
/// knob transforms into Liquid Glass during interaction" — Adopting Liquid
/// Glass). Drawing that knob by hand would only imitate it. Older systems get
/// a knob-less pill track in the pre-Tahoe Control Center style.
///
/// Both variants also follow the scroll wheel / two-finger scrolling while
/// the pointer is over them.
struct BrightnessSlider: View {
    /// Current value, 0...1.
    let value: Double
    let isEnabled: Bool
    let accessibilityLabel: String
    let onChange: (Double) -> Void

    @State private var isHovering = false
    @State private var scrollMonitor = ScrollWheelMonitor()

    init(
        value: Double,
        isEnabled: Bool = true,
        accessibilityLabel: String,
        onChange: @escaping (Double) -> Void
    ) {
        self.value = value
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.onChange = onChange
    }

    var body: some View {
        slider
            .onHover { isHovering = $0 }
            .onAppear { scrollMonitor.start() }
            .onDisappear { scrollMonitor.stop() }
            .background(scrollHandlerUpdater)
    }

    @ViewBuilder
    private var slider: some View {
        if #available(macOS 26.0, *) {
            SystemBrightnessSlider(
                value: value,
                isEnabled: isEnabled,
                accessibilityLabel: accessibilityLabel,
                onChange: onChange
            )
        } else {
            PillBrightnessSlider(
                value: value,
                isEnabled: isEnabled,
                accessibilityLabel: accessibilityLabel,
                onChange: onChange
            )
        }
    }

    /// Keeps the monitor's handler pointed at the latest value/closure. Using
    /// a zero-size background avoids side effects inside `body`.
    private var scrollHandlerUpdater: some View {
        Color.clear
            .onAppear(perform: updateScrollHandler)
            .onChange(of: value) { _, _ in updateScrollHandler() }
            .onChange(of: isHovering) { _, _ in updateScrollHandler() }
            .onChange(of: isEnabled) { _, _ in updateScrollHandler() }
    }

    private func updateScrollHandler() {
        scrollMonitor.value = value
        scrollMonitor.onChange = (isEnabled && isHovering) ? onChange : nil
    }
}

private func percentText(_ value: Double) -> String {
    "\(Int((min(max(value, 0), 1) * 100).rounded())) %"
}

// MARK: - macOS 26+: system slider

@available(macOS 26.0, *)
private struct SystemBrightnessSlider: View {
    let value: Double
    let isEnabled: Bool
    let accessibilityLabel: String
    let onChange: (Double) -> Void

    var body: some View {
        Slider(
            value: Binding(
                get: { isEnabled ? min(max(value, 0), 1) : 0 },
                set: { onChange($0) }
            ),
            in: 0...1
        )
        .labelsHidden()
        // Control Center's knob and track proportions.
        .controlSize(.small)
        // Control Center fills its sliders in white, not the accent color.
        .tint(.white)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isEnabled ? percentText(value) : "Indisponible")
    }
}

// MARK: - Before macOS 26: knob-less pill track

/// Thin pill track with a white fill and no knob. Click or drag anywhere on
/// the track to set the value.
private struct PillBrightnessSlider: View {
    let value: Double
    let isEnabled: Bool
    let accessibilityLabel: String
    let onChange: (Double) -> Void

    /// Value shown while the user is dragging, so the fill tracks the pointer
    /// exactly even if the owner's update arrives a tick later (or a refresh
    /// lands mid-drag).
    @State private var dragValue: Double?
    @Environment(\.colorScheme) private var colorScheme

    private static let trackHeight: CGFloat = 5
    private static let hitHeight: CGFloat = 22
    private static let accessibilityStep = 0.05

    private var displayedValue: Double {
        min(max(dragValue ?? value, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor)
                Capsule(style: .continuous)
                    .fill(.white)
                    .frame(width: fillWidth(in: width))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.18), radius: 0.5, y: 0.25)
            }
            .frame(height: Self.trackHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width), including: isEnabled ? .all : .none)
        }
        .frame(height: Self.hitHeight)
        .transaction { $0.animation = nil }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isEnabled ? percentText(displayedValue) : "Indisponible")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: onChange(min(value + Self.accessibilityStep, 1))
            case .decrement: onChange(max(value - Self.accessibilityStep, 0))
            @unknown default: break
            }
        }
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        guard isEnabled else { return 0 }
        // Keep a visible round cap at small non-zero values, like Control Center.
        let raw = width * displayedValue
        return displayedValue > 0 ? max(raw, Self.trackHeight) : 0
    }

    private var trackColor: Color {
        if colorScheme == .dark {
            return .white.opacity(isEnabled ? 0.16 : 0.08)
        }
        return .black.opacity(isEnabled ? 0.12 : 0.06)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { gesture in
                let newValue = min(max(gesture.location.x / width, 0), 1)
                dragValue = newValue
                onChange(newValue)
            }
            .onEnded { gesture in
                let newValue = min(max(gesture.location.x / width, 0), 1)
                onChange(newValue)
                dragValue = nil
            }
    }
}

// MARK: - Scroll wheel

/// Local `NSEvent` monitor that turns scroll-wheel / trackpad scrolling into
/// value changes while `onChange` is set (i.e. while the slider is hovered).
@MainActor
final class ScrollWheelMonitor {
    /// Last known value; advanced locally so consecutive scroll events
    /// accumulate even before the owner's update comes back.
    var value: Double = 0
    /// Receives the new value. Scroll events are swallowed while it is set.
    var onChange: ((Double) -> Void)?
    private var token: Any?

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let delta = Self.valueDelta(for: event)
            // Local monitors run on the main thread.
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, let onChange = self.onChange else { return false }
                if delta != 0 {
                    self.value = min(max(self.value + delta, 0), 1)
                    onChange(self.value)
                }
                return true
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        onChange = nil
    }

    /// Maps physical motion to a value change: fingers/wheel up or right
    /// brighten, regardless of the "natural scrolling" preference.
    nonisolated private static func valueDelta(for event: NSEvent) -> Double {
        let inverted = event.isDirectionInvertedFromDevice
        let up = Double(inverted ? -event.scrollingDeltaY : event.scrollingDeltaY)
        let right = Double(inverted ? event.scrollingDeltaX : -event.scrollingDeltaX)
        let motion = abs(up) >= abs(right) ? up : right
        if event.hasPreciseScrollingDeltas {
            return motion / 400 // ~400 pt of trackpad travel for the full range
        }
        return motion * 0.02 // mouse wheel: ~2 % per line
    }
}
