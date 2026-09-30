import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A field showing an action's shortcut. Click it, then press the new
/// combination: Esc cancels, ⌫ clears. A combination that cannot be used is
/// refused with a beep and the reason (see `ShortcutRecorderSession`).
struct ShortcutRecorder: View {
    static let width: CGFloat = 150

    let action: ShortcutAction
    private let store = ShortcutStore.shared
    private let session = ShortcutRecorderSession.shared

    var body: some View {
        let isRecording = session.action == action
        let shortcut = store.shortcut(for: action)
        Text(title(isRecording: isRecording, shortcut: shortcut))
            .foregroundStyle(shortcut == nil || isRecording ? .secondary : .primary)
            .lineLimit(1)
            // Centered in the whole field, clear of the clear button.
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                if shortcut != nil, !isRecording {
                    Button {
                        store.setShortcut(nil, for: action)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 5)
                    .help("Effacer le raccourci")
                    .accessibilityLabel("Effacer le raccourci")
                }
            }
            .frame(width: Self.width, height: 22)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: isRecording ? 2 : 1)
            }
            .contentShape(.rect)
            .onTapGesture { session.toggle(action) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(action.title)
            .accessibilityValue(shortcut?.displayString ?? "Aucun")
            .accessibilityAction { session.toggle(action) }
    }

    private func title(isRecording: Bool, shortcut: KeyboardShortcut?) -> String {
        if isRecording {
            let held = KeyboardShortcut.symbols(for: session.modifiers)
            return held.isEmpty ? "Saisir un raccourci" : held + "…"
        }
        return shortcut?.displayString ?? "Aucun raccourci"
    }
}

/// The one recording in progress, shared by all recorders: a local key
/// monitor on the settings window, and global hot keys suspended meanwhile.
@MainActor
@Observable
final class ShortcutRecorderSession {
    static let shared = ShortcutRecorderSession()

    struct Rejection: Equatable {
        let action: ShortcutAction
        let message: String
    }

    /// Action being recorded.
    private(set) var action: ShortcutAction?
    /// Modifiers held so far, shown while recording.
    private(set) var modifiers: NSEvent.ModifierFlags = []
    /// Why the last combination was refused, until recording ends.
    private(set) var rejection: Rejection?

    @ObservationIgnored private let store = ShortcutStore.shared
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// A click anywhere ends recording on mouse down, before the field it
    /// hit gets it on mouse up: clicking the recording field only stops it.
    @ObservationIgnored private var stoppedByClick: (action: ShortcutAction, date: Date)?

    private init() {}

    func toggle(_ action: ShortcutAction) {
        if let stopped = stoppedByClick, stopped.action == action, Date().timeIntervalSince(stopped.date) < 0.5 {
            stoppedByClick = nil
            return
        }
        if self.action == action {
            stop()
        } else {
            start(action)
        }
    }

    func stop() {
        guard action != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        action = nil
        modifiers = []
        rejection = nil
        store.isRecording = false
    }

    private func start(_ action: ShortcutAction) {
        stop()
        self.action = action
        modifiers = NSEvent.modifierFlags.intersection(KeyboardShortcut.relevantModifiers)
        store.isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            // `keyCode` raises on mouse events: read it for keys only.
            let type = event.type
            let keyCode = type == .keyDown ? Int(event.keyCode) : 0
            let flags = event.modifierFlags
            // Local monitors run on the main thread.
            let consumed = MainActor.assumeIsolated {
                self?.handle(type, keyCode: keyCode, modifierFlags: flags) ?? false
            }
            return consumed ? nil : event
        }
        // Switching window or app ends recording.
        for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
    }

    /// Returns whether the event is consumed (keys never reach the window
    /// while recording; clicks always do).
    private func handle(_ type: NSEvent.EventType, keyCode: Int, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard let action else { return false }
        switch type {
        case .flagsChanged:
            modifiers = modifierFlags.intersection(KeyboardShortcut.relevantModifiers)
            return false
        case .keyDown:
            let shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifierFlags)
            if shortcut.modifiers.isEmpty {
                switch keyCode {
                case kVK_Escape:
                    stop()
                    return true
                case kVK_Delete, kVK_ForwardDelete:
                    store.setShortcut(nil, for: action)
                    stop()
                    return true
                default:
                    break
                }
            }
            if let message = store.conflict(for: shortcut, action: action) {
                NSSound.beep()
                rejection = Rejection(action: action, message: message)
            } else {
                store.setShortcut(shortcut, for: action)
                stop()
            }
            return true
        default:
            stoppedByClick = (action, Date())
            stop()
            return false
        }
    }
}
