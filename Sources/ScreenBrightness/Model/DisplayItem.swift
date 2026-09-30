import CoreGraphics

/// One screen as shown in the menu.
struct DisplayItem: Identifiable, Equatable {
    enum Backend: Equatable {
        /// Built-in panel, driven by the private DisplayServices framework.
        case builtIn
        /// External monitor reachable over DDC/CI. The lower part of the
        /// slider range continues with software dimming down to black.
        case ddc
        /// External monitor without DDC: software dimming only (gamma).
        case software
        /// Monitor that did not answer DDC; the slider is disabled.
        case unsupported
    }

    let id: CGDirectDisplayID
    var name: String
    /// Normalised brightness, 0...1.
    var brightness: Double
    var backend: Backend

    var isControllable: Bool { backend != .unsupported }
}
