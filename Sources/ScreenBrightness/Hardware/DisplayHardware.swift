import CoreGraphics
import IOKit

/// Enumerates screens and reads/writes their brightness.
/// Must only be used from one serial queue (see DisplayController).
/// `@unchecked Sendable`: confinement to that queue is what makes it safe.
///
/// External screens use combined dimming: the top of the slider range drives
/// the monitor's backlight over DDC, the bottom `softwareRange` keeps the
/// backlight at its minimum and fades the picture to black via gamma.
final class DisplayHardware: @unchecked Sendable {
    /// Share of the slider below which a DDC screen is dimmed in software.
    static let softwareRange = 0.2

    private struct DDCTarget {
        let channel: DDCChannel
        let maxValue: Int
        /// Last value sent or read, to skip redundant writes (e.g. 0 while
        /// dragging inside the software range).
        var lastValue: Int
    }

    private var ddcTargets: [CGDirectDisplayID: DDCTarget] = [:]
    private var softwareTargets: Set<CGDirectDisplayID> = []
    private let dimmer = GammaDimmer()

    /// `names` maps display IDs to user-facing names (resolved on the main thread).
    func discover(names: [CGDirectDisplayID: String]) -> [DisplayItem] {
        ddcTargets.removeAll()
        softwareTargets.removeAll()
        let candidates = AVServiceLocator.candidates()
        defer { candidates.forEach { IOObjectRelease($0.service) } }

        var used = Set<Int>()
        return onlineDisplays().map { id in
            let name = names[id] ?? "Écran \(id)"
            if CGDisplayIsBuiltin(id) != 0 {
                if let value = BuiltInDisplay.brightness(of: id) {
                    return DisplayItem(id: id, name: name, brightness: value, backend: .builtIn)
                }
                return DisplayItem(id: id, name: name, brightness: 0, backend: .unsupported)
            }
            if let index = AVServiceLocator.match(id, in: candidates, excluding: used),
               let channel = DDCChannel(service: candidates[index].service),
               let reading = channel.read(DDCChannel.brightnessVCP) {
                used.insert(index)
                ddcTargets[id] = DDCTarget(channel: channel, maxValue: reading.max, lastValue: reading.current)
                return DisplayItem(id: id, name: name, brightness: ddcBrightness(reading, for: id), backend: .ddc)
            }
            softwareTargets.insert(id)
            return DisplayItem(id: id, name: name, brightness: dimmer.factor(for: id), backend: .software)
        }
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        let value = min(max(value, 0), 1)
        if let target = ddcTargets[id] {
            let range = Self.softwareRange
            if value >= range {
                dimmer.setFactor(1, for: id)
                writeDDC(Int(((value - range) / (1 - range) * Double(target.maxValue)).rounded()), for: id)
            } else {
                writeDDC(0, for: id)
                dimmer.setFactor(value / range, for: id)
            }
        } else if softwareTargets.contains(id) {
            dimmer.setFactor(value, for: id)
        } else if CGDisplayIsBuiltin(id) != 0 {
            BuiltInDisplay.setBrightness(value, of: id)
        }
    }

    /// Re-applies software dims to online screens; call after each discovery,
    /// since macOS resets gamma tables on reconfiguration and wake.
    func reapplySoftwareDimming() {
        dimmer.reapply(to: onlineDisplays())
    }

    /// Restores every screen's ColorSync gamma (on quit).
    func restoreSoftwareDimming() {
        dimmer.restoreAll()
    }

    /// Slider position for a DDC reading. The backlight covers the range above
    /// `softwareRange`; at DDC 0 an active software dim places it below.
    private func ddcBrightness(_ reading: (current: Int, max: Int), for id: CGDirectDisplayID) -> Double {
        let range = Self.softwareRange
        let factor = dimmer.factor(for: id)
        if factor < 1 {
            if reading.current == 0 { return range * factor }
            // The backlight was raised elsewhere (OSD buttons, another app):
            // the dim no longer matches, drop it.
            dimmer.setFactor(1, for: id)
        }
        let backlight = min(max(Double(reading.current) / Double(reading.max), 0), 1)
        return range + (1 - range) * backlight
    }

    private func writeDDC(_ value: Int, for id: CGDirectDisplayID) {
        guard var target = ddcTargets[id], target.lastValue != value else { return }
        if target.channel.write(DDCChannel.brightnessVCP, value: value) {
            target.lastValue = value
            ddcTargets[id] = target
        }
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        // Skip mirrored secondaries: they share the primary's panel settings.
        return ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
    }
}
