import Foundation
import Observation

/// User preferences for the keyboard brightness keys, kept in UserDefaults.
@MainActor
@Observable
final class BrightnessKeyPreferences {
    static let shared = BrightnessKeyPreferences()

    private static let functionKeysKey = "functionKeysControlBrightness"

    /// Plain F1 / F2 dim / brighten the screen under the pointer, for
    /// keyboards that send function keys instead of brightness codes.
    /// Off by default.
    var functionKeysEnabled: Bool {
        didSet {
            guard functionKeysEnabled != oldValue else { return }
            UserDefaults.standard.set(functionKeysEnabled, forKey: Self.functionKeysKey)
            onChange?()
        }
    }

    /// Called after any preference changed.
    @ObservationIgnored var onChange: (() -> Void)?

    private init() {
        functionKeysEnabled = UserDefaults.standard.bool(forKey: Self.functionKeysKey)
    }
}
