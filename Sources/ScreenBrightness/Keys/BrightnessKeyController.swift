import AppKit

/// Makes the keyboard brightness keys (and, if enabled, plain F1/F2) drive
/// the screen under the pointer, MacBook-style, with the HUD on that screen.
/// The event tap is installed whenever Accessibility is granted, and removed
/// if it is revoked.
@MainActor
final class BrightnessKeyController {
    private let stepper: BrightnessStepper
    private let permission = AccessibilityPermission.shared
    private let preferences = BrightnessKeyPreferences.shared
    private lazy var tap = BrightnessKeyTap { [weak self] event in
        // Tap thread: hop to the main thread and return at once.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    init(stepper: BrightnessStepper) {
        self.stepper = stepper
    }

    func start() {
        tap.functionKeysEnabled = preferences.functionKeysEnabled
        preferences.onChange = { [weak self] in
            guard let self else { return }
            self.tap.functionKeysEnabled = self.preferences.functionKeysEnabled
        }
        permission.onChange = { [weak self] _ in self?.updateTap() }
        permission.startMonitoring()
        updateTap()
    }

    private func updateTap() {
        if permission.isTrusted {
            // Right after the switch is flipped, trust can be reported a
            // moment before the tap is allowed: retry until it installs.
            if !tap.start() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.updateTap() }
            }
        } else {
            tap.stop()
        }
    }

    /// One press or auto-repeat: one step on the screen under the pointer.
    private func handle(_ event: BrightnessKeyEvent) {
        stepper.stepScreenUnderPointer(by: event.direction == .up ? event.step : -event.step)
    }
}

/// One brightness step, Apple-style, with the HUD: what a brightness key
/// press does. Shared by the brightness keys and the global shortcuts.
@MainActor
struct BrightnessStepper {
    let displays: DisplayController
    let osd: OSDController

    /// Steps the screen under the pointer by `delta` and shows the HUD there.
    /// Screens without brightness control are left alone.
    func stepScreenUnderPointer(by delta: Double) {
        guard let display = displays.displayUnderPointer(), display.isControllable,
              let level = displays.adjustBrightness(by: delta, for: display.id) else { return }
        osd.show(level: level, on: display.id)
    }
}
