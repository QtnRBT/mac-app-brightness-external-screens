import AppKit
import Carbon.HIToolbox

/// System-wide hot keys through Carbon's `RegisterEventHotKey`: the one
/// global keyboard API that needs no Accessibility or Input Monitoring
/// permission. Handlers run on the main thread.
///
/// A hot key registered with `repeats` fires again at the keyboard's repeat
/// rate (System Settings › Keyboard) while it is held, like a key typed in
/// a text field.
@MainActor
final class HotKeyCenter {
    private struct HotKey {
        let ref: EventHotKeyRef
        let shortcut: KeyboardShortcut
        let repeats: Bool
        let action: () -> Void
    }

    /// "SBrt": tells our hot keys apart from any other in the process.
    private static let signature: OSType = 0x5342_7274

    private var hotKeys: [UInt32: HotKey] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var heldID: UInt32?
    /// Last press event for `heldID`, including any repeated by the system.
    private var lastPress = Date.distantPast
    private var repeatTimer: Timer?

    /// Registers `shortcut` system-wide. Returns Carbon's status: `noErr`,
    /// or e.g. `eventHotKeyExistsErr` if the combination is already taken.
    @discardableResult
    func register(_ shortcut: KeyboardShortcut, repeats: Bool, action: @escaping () -> Void) -> OSStatus {
        installEventHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return status == noErr ? OSStatus(eventInternalErr) : status }
        hotKeys[id] = HotKey(ref: ref, shortcut: shortcut, repeats: repeats, action: action)
        return noErr
    }

    func unregisterAll() {
        stopRepeating()
        for hotKey in hotKeys.values {
            UnregisterEventHotKey(hotKey.ref)
        }
        hotKeys.removeAll()
    }

    // MARK: - Events

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        let types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            // The application event target dispatches on the main thread.
            return MainActor.assumeIsolated { center.handle(hotKeyID, isPress: isPress) }
        }, types.count, types, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    private func handle(_ hotKeyID: EventHotKeyID, isPress: Bool) -> OSStatus {
        guard hotKeyID.signature == Self.signature, let hotKey = hotKeys[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }
        if isPress {
            // Presses the system repeats while the key is held are ignored
            // (we repeat at our own pace). Long after the last one, the
            // release was missed: this is a new press.
            let now = Date()
            defer { lastPress = now }
            if heldID == hotKeyID.id, now.timeIntervalSince(lastPress) < NSEvent.keyRepeatDelay + 0.2 {
                return noErr
            }
            stopRepeating()
            heldID = hotKeyID.id
            hotKey.action()
            if hotKey.repeats { startRepeating(hotKeyID.id) }
        } else if heldID == hotKeyID.id {
            stopRepeating()
        }
        return noErr
    }

    // MARK: - Key repeat

    private func startRepeating(_ id: UInt32) {
        let timer = Timer(timeInterval: NSEvent.keyRepeatDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.repeatTick(id) }
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func repeatTick(_ id: UInt32) {
        guard heldID == id, let hotKey = hotKeys[id] else { return stopRepeating() }
        // A release can be missed (e.g. the key comes up while another app
        // grabs the keyboard): stop once the modifiers are no longer held.
        let held = NSEvent.modifierFlags.intersection(KeyboardShortcut.relevantModifiers)
        guard held == hotKey.shortcut.modifiers else { return stopRepeating() }
        hotKey.action()
        let timer = Timer(timeInterval: NSEvent.keyRepeatInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.repeatTick(id) }
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        heldID = nil
    }
}
