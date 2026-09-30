import AppKit
import CoreGraphics
import Observation

/// Source of truth for the menu. All hardware I/O runs on a serial background
/// queue; the UI only ever touches `displays` on the main actor.
@MainActor
@Observable
final class DisplayController {
    private(set) var displays: [DisplayItem] = []
    private(set) var isRefreshing = false

    @ObservationIgnored private let hardware = DisplayHardware()
    @ObservationIgnored private let queue = DispatchQueue(label: "ScreenBrightness.hardware", qos: .userInitiated)
    @ObservationIgnored private var pendingWrites: [CGDirectDisplayID: Double] = [:]
    @ObservationIgnored private var writeScheduled: Set<CGDirectDisplayID> = []
    @ObservationIgnored private var refreshWorkItem: DispatchWorkItem?

    init() {
        refresh()
        observeSystemChanges()
    }

    /// Re-discovers screens and re-reads their brightness (e.g. after the user
    /// changed it with the monitor's own buttons).
    func refresh() {
        isRefreshing = true
        let names = Self.screenNames()
        queue.async { [hardware] in
            let found = hardware.discover(names: names)
            DispatchQueue.main.async {
                // A slider still being written wins over the (older) reading.
                self.displays = found.map { item in
                    guard self.writeScheduled.contains(item.id),
                          let local = self.displays.first(where: { $0.id == item.id }) else { return item }
                    var merged = item
                    merged.brightness = local.brightness
                    return merged
                }
                self.isRefreshing = false
            }
        }
    }

    /// Sets brightness (0...1). Updates the UI immediately and coalesces the
    /// hardware writes so dragging a slider never floods the DDC bus.
    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        let clamped = min(max(value, 0), 1)
        guard let index = displays.firstIndex(where: { $0.id == id }),
              displays[index].isControllable else { return }
        displays[index].brightness = clamped
        pendingWrites[id] = clamped
        guard !writeScheduled.contains(id) else { return }
        writeScheduled.insert(id)
        flushWrite(for: id)
    }

    private func flushWrite(for id: CGDirectDisplayID) {
        guard let value = pendingWrites.removeValue(forKey: id) else {
            writeScheduled.remove(id)
            return
        }
        queue.async { [hardware] in
            hardware.setBrightness(value, for: id)
            DispatchQueue.main.async { self.flushWrite(for: id) }
        }
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return names
    }

    private func observeSystemChanges() {
        let callback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
            guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
            let controller = Unmanaged<DisplayController>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { controller.scheduleRefresh() }
        }
        CGDisplayRegisterReconfigurationCallback(callback, Unmanaged.passUnretained(self).toOpaque())

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
    }

    /// Screens take a moment to settle after a (re)connect or wake.
    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }
}
