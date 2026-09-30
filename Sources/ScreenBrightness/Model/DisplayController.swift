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
    /// Each screen's share of the brightest one, captured the first time the
    /// master slider moves, so dragging it to black and back restores the
    /// original differences. Dropped when a single screen is set on its own.
    @ObservationIgnored private var masterRatios: [CGDirectDisplayID: Double]?

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
            // macOS resets gamma on reconfiguration / wake: put dims back.
            hardware.reapplySoftwareDimming()
            DispatchQueue.main.async {
                if Set(found.map(\.id)) != Set(self.displays.map(\.id)) {
                    self.masterRatios = nil
                }
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
        masterRatios = nil
        apply(value, for: id)
    }

    /// Level shown by the master slider: the brightest controllable screen.
    /// `nil` when fewer than two screens can be controlled.
    var masterBrightness: Double? {
        let controllable = displays.filter(\.isControllable)
        guard controllable.count >= 2 else { return nil }
        return controllable.map(\.brightness).max()
    }

    /// Moves every controllable screen together, proportionally: the
    /// brightest one goes to `value`, the others keep their share of it.
    func setMasterBrightness(_ value: Double) {
        let controllable = displays.filter(\.isControllable)
        guard controllable.count >= 2 else { return }
        let ratios = masterRatios ?? Self.masterRatios(for: controllable)
        masterRatios = ratios
        let clamped = min(max(value, 0), 1)
        for display in controllable {
            apply(clamped * (ratios[display.id] ?? 1), for: display.id)
        }
    }

    /// Each display's brightness relative to the brightest one (1 for all
    /// when every screen is at 0, so the master then moves them together).
    nonisolated static func masterRatios(for displays: [DisplayItem]) -> [CGDirectDisplayID: Double] {
        let top = displays.map(\.brightness).max() ?? 0
        return Dictionary(uniqueKeysWithValues: displays.map {
            ($0.id, top > 0 ? min(max($0.brightness / top, 0), 1) : 1)
        })
    }

    private func apply(_ value: Double, for id: CGDirectDisplayID) {
        let clamped = min(max(value, 0), 1)
        guard let index = displays.firstIndex(where: { $0.id == id }),
              displays[index].isControllable else { return }
        displays[index].brightness = clamped
        pendingWrites[id] = clamped
        guard !writeScheduled.contains(id) else { return }
        writeScheduled.insert(id)
        flushWrite(for: id)
    }

    /// Moves brightness one step of `delta` (e.g. ±1/16) the way the Mac's
    /// brightness keys do: from a value between two steps, the first press
    /// lands on the next step in that direction instead of adding `delta`.
    /// Returns the new level, or `nil` if the screen is unknown or not
    /// controllable.
    @discardableResult
    func adjustBrightness(by delta: Double, for id: CGDirectDisplayID) -> Double? {
        guard let display = displays.first(where: { $0.id == id }), display.isControllable else { return nil }
        setBrightness(Self.steppedBrightness(from: display.brightness, by: delta), for: id)
        return displays.first(where: { $0.id == id })?.brightness
    }

    /// Screen under the mouse pointer, if it is one of `displays`.
    func displayUnderPointer() -> DisplayItem? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return displays.first(where: { $0.id == number.uint32Value })
    }

    /// Next multiple of `|delta|` above (`delta > 0`) or below `value`,
    /// clamped to 0...1. Values within a hair of a step count as on it, so
    /// a level read back as 0.49999 still moves a full step.
    nonisolated static func steppedBrightness(from value: Double, by delta: Double) -> Double {
        let step = abs(delta)
        guard step > 0 else { return min(max(value, 0), 1) }
        let position = value / step
        let tolerance = 0.001
        let target = delta > 0
            ? (floor(position + tolerance) + 1) * step
            : (ceil(position - tolerance) - 1) * step
        return min(max(target, 0), 1)
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

        // Never leave a screen dimmed in software once the app is gone.
        // `sync` runs after any write still queued, so none can re-dim.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [queue, hardware] _ in
            queue.sync { hardware.restoreSoftwareDimming() }
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
