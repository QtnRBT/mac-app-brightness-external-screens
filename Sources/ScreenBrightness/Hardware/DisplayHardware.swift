import CoreGraphics
import IOKit

/// Enumerates screens and reads/writes their brightness.
/// Must only be used from one serial queue (see DisplayController).
/// `@unchecked Sendable`: confinement to that queue is what makes it safe.
final class DisplayHardware: @unchecked Sendable {
    private struct DDCTarget {
        let channel: DDCChannel
        let maxValue: Int
    }

    private var ddcTargets: [CGDirectDisplayID: DDCTarget] = [:]

    /// `names` maps display IDs to user-facing names (resolved on the main thread).
    func discover(names: [CGDirectDisplayID: String]) -> [DisplayItem] {
        ddcTargets.removeAll()
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
                ddcTargets[id] = DDCTarget(channel: channel, maxValue: reading.max)
                let value = Double(reading.current) / Double(reading.max)
                return DisplayItem(id: id, name: name, brightness: min(max(value, 0), 1), backend: .ddc)
            }
            return DisplayItem(id: id, name: name, brightness: 0, backend: .unsupported)
        }
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        if let target = ddcTargets[id] {
            target.channel.write(DDCChannel.brightnessVCP, value: Int((value * Double(target.maxValue)).rounded()))
        } else if CGDisplayIsBuiltin(id) != 0 {
            BuiltInDisplay.setBrightness(value, of: id)
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
