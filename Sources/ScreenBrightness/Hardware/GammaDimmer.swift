import CoreGraphics

/// One display's gamma (transfer) table, one ramp per channel.
struct GammaTable: Equatable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]

    /// Reads the table currently applied to a display.
    static func current(of id: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(id)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &red, &green, &blue, &count) == .success, count > 0 else {
            return nil
        }
        let used = Int(count)
        return GammaTable(red: Array(red.prefix(used)), green: Array(green.prefix(used)), blue: Array(blue.prefix(used)))
    }

    /// Every entry multiplied by `factor`: the curve keeps its shape, only
    /// the output ceiling drops, down to black at 0.
    func scaled(by factor: Double) -> GammaTable {
        let factor = CGGammaValue(factor)
        return GammaTable(red: red.map { $0 * factor }, green: green.map { $0 * factor }, blue: blue.map { $0 * factor })
    }

    @discardableResult
    func apply(to id: CGDirectDisplayID) -> Bool {
        CGSetDisplayTransferByTable(id, UInt32(red.count), red, green, blue) == .success
    }
}

/// Software dimming by scaling each display's gamma table, so a screen can go
/// fully black (a monitor's DDC minimum only lowers the backlight).
///
/// The original table is captured just before a display's first dim and put
/// back when its factor returns to 1. macOS resets gamma on reconfiguration,
/// wake and ColorSync changes, hence `reapply(to:)`.
/// Not thread-safe: confined to DisplayHardware's serial queue.
final class GammaDimmer {
    private var originals: [CGDirectDisplayID: GammaTable] = [:]
    private var factors: [CGDirectDisplayID: Double] = [:]

    /// Active software factor for a display, 1 when it is untouched.
    func factor(for id: CGDirectDisplayID) -> Double {
        factors[id] ?? 1
    }

    /// Dims a display to `factor` (0 = black, 1 = original table).
    @discardableResult
    func setFactor(_ factor: Double, for id: CGDirectDisplayID) -> Bool {
        let factor = min(max(factor, 0), 1)
        guard factor < 1 else {
            factors[id] = nil
            // Nothing captured means we never touched this display.
            return originals.removeValue(forKey: id)?.apply(to: id) ?? true
        }
        if originals[id] == nil {
            guard let table = GammaTable.current(of: id) else { return false }
            originals[id] = table
        }
        guard let original = originals[id] else { return false }
        factors[id] = factor
        return original.scaled(by: factor).apply(to: id)
    }

    /// Re-applies active dims after macOS reset the gamma tables.
    func reapply(to ids: [CGDirectDisplayID]) {
        for id in ids {
            if let factor = factors[id], let original = originals[id] {
                original.scaled(by: factor).apply(to: id)
            }
        }
    }

    /// Puts every display back on its ColorSync profile and forgets all dims.
    func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
        originals.removeAll()
        factors.removeAll()
    }
}
