import AppKit
import CoreGraphics
import os

/// Active `CGEventTap` that swallows brightness key presses and reports them.
///
/// The tap sits at the head of the session (`.cgSessionEventTap`,
/// `.headInsertEventTap`, `.defaultTap`), like MonitorControl's MediaKeyTap,
/// so a swallowed press reaches neither the frontmost app nor macOS's own
/// brightness handling. It runs on its own thread: every key event of the
/// session passes through the callback, so it must never wait on the main
/// thread. The callback only decodes, then hands presses to `onPress` (which
/// hops to the main thread itself).
///
/// Needs Accessibility trust; `start()` fails without it.
final class BrightnessKeyTap: @unchecked Sendable {
    private struct Shared {
        var port: CFMachPort?
        var runLoop: CFRunLoop?
        var functionKeysEnabled = false
    }

    /// Called on the tap's thread for each press or auto-repeat swallowed.
    private let onPress: @Sendable (BrightnessKeyEvent) -> Void
    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    private let logger = Logger(subsystem: "ScreenBrightness", category: "BrightnessKeyTap")
    /// Keys whose press was swallowed; their release is swallowed too.
    /// Only touched on the tap's thread.
    private var heldKeys: Set<Int> = []

    init(onPress: @escaping @Sendable (BrightnessKeyEvent) -> Void) {
        self.onPress = onPress
    }

    deinit {
        stop()
    }

    var isRunning: Bool { shared.withLock { $0.port != nil } }

    /// Whether plain F1/F2 act as brightness keys. Read by the callback.
    var functionKeysEnabled: Bool {
        get { shared.withLock { $0.functionKeysEnabled } }
        set { shared.withLock { $0.functionKeysEnabled = newValue } }
    }

    /// Installs the tap. Returns `false` if the system refused it (no
    /// Accessibility trust).
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventMask(BrightnessKeyDecoder.systemDefinedEventType))
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: brightnessKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Event tap creation failed (Accessibility not granted?)")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }
        shared.withLock { $0.port = port }

        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            self?.shared.withLock { $0.runLoop = runLoop }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            // Returns once the port (hence the source) is invalidated.
            CFRunLoopRun()
        }
        thread.name = "ScreenBrightness.BrightnessKeyTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        logger.info("Brightness key tap installed")
        return true
    }

    /// Removes the tap (e.g. when Accessibility trust is revoked).
    func stop() {
        let (port, runLoop) = shared.withLock { state -> (CFMachPort?, CFRunLoop?) in
            defer { state.port = nil; state.runLoop = nil }
            return (state.port, state.runLoop)
        }
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop { CFRunLoopStop(runLoop) }
        logger.info("Brightness key tap removed")
    }

    // MARK: - Callback (tap thread)

    /// Whether to swallow `event`. Internal (not private) for tests.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system turns a tap off if it is too slow or on some user
            // input; turn it back on.
            if let port = shared.withLock({ $0.port }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            logger.info("Event tap re-enabled after being disabled (\(type.rawValue))")
            return false
        case .keyDown, .keyUp:
            let decoded = BrightnessKeyDecoder.decodeKey(
                keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                isKeyDown: type == .keyDown,
                isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)),
                functionKeysEnabled: functionKeysEnabled
            )
            return consume(decoded)
        default:
            guard type.rawValue == BrightnessKeyDecoder.systemDefinedEventType,
                  let nsEvent = NSEvent(cgEvent: event)
            else { return false }
            let decoded = BrightnessKeyDecoder.decodeSystemDefined(
                subtype: Int(nsEvent.subtype.rawValue),
                data1: nsEvent.data1,
                modifiers: nsEvent.modifierFlags
            )
            return consume(decoded)
        }
    }

    /// Whether to swallow the event; reports presses.
    private func consume(_ event: BrightnessKeyEvent?) -> Bool {
        guard let event else { return false }
        switch event.phase {
        case .down, .repeated:
            heldKeys.insert(event.keyID)
            onPress(event)
            return true
        case .up:
            return heldKeys.remove(event.keyID) != nil
        }
    }
}

private let brightnessKeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<BrightnessKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
