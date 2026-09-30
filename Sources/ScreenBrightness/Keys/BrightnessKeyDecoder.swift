import AppKit

/// A brightness key press, release or auto-repeat, decoded from a raw event.
struct BrightnessKeyEvent: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case up, down
    }

    enum Phase: Equatable, Sendable {
        case down, repeated, up
    }

    let direction: Direction
    let phase: Phase
    /// Option+Shift held: Apple's quarter steps (1/64 instead of 1/16).
    let isFine: Bool
    /// Identifies the physical key, to pair a release with its press.
    let keyID: Int

    /// Fraction of the range one press moves, like the Mac's own keys.
    var step: Double { isFine ? 1.0 / 64 : 1.0 / 16 }
}

/// Pure decoding of the events a keyboard sends for brightness. No state,
/// no I/O: safe to call from the event tap's thread.
///
/// Three sources, all seen by a session event tap:
/// - `NX_SYSDEFINED` events, subtype 8 (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`),
///   whose `data1` packs the key type in its high 16 bits (2 =
///   `NX_KEYTYPE_BRIGHTNESS_UP`, 3 = `NX_KEYTYPE_BRIGHTNESS_DOWN`) and the
///   key state in its low 16 bits (`0xA` = down, `0xB` = up in bits 8–15,
///   bit 0 = auto-repeat). Apple keyboards' F1/F2 in their media role, and
///   HID "Consumer Brightness" usages (e.g. QMK's `KC_BRIU` / `KC_BRID`).
/// - Key-down/up events with virtual key codes 144 (up) / 145 (down), which
///   some keyboards send for the brightness keys (MonitorControl's
///   MediaKeyTap handles them too).
/// - Plain F1 (122, down) / F2 (120, up), only when the user opted in, for
///   keyboards that send function keys instead of brightness codes.
enum BrightnessKeyDecoder {
    static let systemDefinedEventType: UInt32 = 14 // NX_SYSDEFINED
    static let auxControlButtonsSubtype = 8 // NX_SUBTYPE_AUX_CONTROL_BUTTONS
    static let keyTypeBrightnessUp = 2 // NX_KEYTYPE_BRIGHTNESS_UP
    static let keyTypeBrightnessDown = 3 // NX_KEYTYPE_BRIGHTNESS_DOWN

    static let keyCodeBrightnessUp = 144
    static let keyCodeBrightnessDown = 145
    static let keyCodeF1 = 122 // kVK_F1
    static let keyCodeF2 = 120 // kVK_F2

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    private static let fineModifiers: NSEvent.ModifierFlags = [.option, .shift]

    /// Decodes an `NX_SYSDEFINED` event. Returns `nil` for anything that is
    /// not a brightness key, and for a press with Option alone, which macOS
    /// uses to open Displays settings.
    static func decodeSystemDefined(
        subtype: Int,
        data1: Int,
        modifiers: NSEvent.ModifierFlags
    ) -> BrightnessKeyEvent? {
        guard subtype == auxControlButtonsSubtype else { return nil }
        let keyType = (data1 & 0xFFFF_0000) >> 16
        let direction: BrightnessKeyEvent.Direction
        switch keyType {
        case keyTypeBrightnessUp: direction = .up
        case keyTypeBrightnessDown: direction = .down
        default: return nil
        }

        let keyFlags = data1 & 0xFFFF
        let phase: BrightnessKeyEvent.Phase
        switch (keyFlags & 0xFF00) >> 8 {
        case 0xA: phase = (keyFlags & 0x1) != 0 ? .repeated : .down
        case 0xB: phase = .up
        default: return nil
        }

        let mods = modifiers.intersection(relevantModifiers)
        if phase != .up, mods == .option { return nil }
        return BrightnessKeyEvent(
            direction: direction,
            phase: phase,
            isFine: mods.isSuperset(of: fineModifiers),
            keyID: 1000 + keyType
        )
    }

    /// Decodes a key-down / key-up event. F1/F2 count only when
    /// `functionKeysEnabled`, and only with no modifier (or Option+Shift for
    /// fine steps), so shortcuts like ⌘F1 keep working. Releases are always
    /// decoded: the caller swallows only those whose press it swallowed.
    static func decodeKey(
        keyCode: Int,
        isKeyDown: Bool,
        isAutorepeat: Bool,
        modifiers: NSEvent.ModifierFlags,
        functionKeysEnabled: Bool
    ) -> BrightnessKeyEvent? {
        let direction: BrightnessKeyEvent.Direction
        let isFunctionKey: Bool
        switch keyCode {
        case keyCodeBrightnessUp: (direction, isFunctionKey) = (.up, false)
        case keyCodeBrightnessDown: (direction, isFunctionKey) = (.down, false)
        case keyCodeF2: (direction, isFunctionKey) = (.up, true)
        case keyCodeF1: (direction, isFunctionKey) = (.down, true)
        default: return nil
        }

        let phase: BrightnessKeyEvent.Phase = isKeyDown ? (isAutorepeat ? .repeated : .down) : .up
        let mods = modifiers.intersection(relevantModifiers)
        let isFine = mods == fineModifiers
        if phase != .up {
            if isFunctionKey {
                guard functionKeysEnabled, mods.isEmpty || isFine else { return nil }
            } else if mods == .option {
                return nil
            }
        }
        return BrightnessKeyEvent(
            direction: direction,
            phase: phase,
            isFine: isFunctionKey ? isFine : mods.isSuperset(of: fineModifiers),
            keyID: keyCode
        )
    }
}
