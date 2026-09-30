import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, as a Carbon hot key sees it: a layout-independent
/// virtual key code and the ⌃ ⌥ ⇧ ⌘ modifiers (nothing else is kept).
struct KeyboardShortcut: Codable, Hashable {
    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// Virtual key code (`kVK_…`).
    let keyCode: UInt32
    private let rawModifiers: UInt

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: rawModifiers) }

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = UInt32(keyCode)
        rawModifiers = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case rawModifiers = "modifiers"
    }

    /// Modifiers in the form `RegisterEventHotKey` expects.
    var carbonModifiers: UInt32 {
        var carbon = 0
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        if modifiers.contains(.command) { carbon |= cmdKey }
        return UInt32(carbon)
    }

    /// F1…F20: usable without modifiers.
    var isFunctionKey: Bool { Self.functionKeyCodes.contains(Int(keyCode)) }

    /// Since macOS 15 a global shortcut needs ⌃ or ⌘ (⌥ and ⇧ alone only
    /// type characters), except on a function key.
    var isValidGlobalShortcut: Bool {
        isFunctionKey || !modifiers.isDisjoint(with: [.control, .command])
    }

    /// "⌃⌥↑", in the menu order ⌃ ⌥ ⇧ ⌘, with the key as printed on the
    /// current keyboard layout.
    var displayString: String { Self.symbols(for: modifiers) + keyName }

    /// The key alone: a symbol for special keys, otherwise the character
    /// the current layout types for it ("A", "Ç"…).
    var keyName: String {
        if let name = Self.specialKeyNames[Int(keyCode)] { return name }
        return Self.character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }

    /// Unmodified character the current keyboard layout produces for
    /// `keyCode` (what menus show as a key equivalent), or `nil`.
    static func character(for keyCode: UInt32) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let layoutSource = source.flatMap(layoutData(of:)) == nil
            ? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
            : source
        guard let layoutSource, let data = layoutData(of: layoutSource) else { return nil }

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        return string.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty ? nil : string
    }

    private static func layoutData(of source: TISInputSource) -> Data? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    /// F1…F20, in order.
    private static let functionKeyCodes = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let specialKeyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "Espace",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_ANSI_KeypadClear: "⌧",
        ]
        for (index, key) in functionKeyCodes.enumerated() { names[key] = "F\(index + 1)" }
        return names
    }()
}
