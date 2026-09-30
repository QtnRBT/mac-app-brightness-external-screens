import AppKit
import ApplicationServices
import Observation

/// Accessibility trust, which the brightness key tap needs. Never prompts on
/// its own: the panel shows a row that calls `request()`. While untrusted it
/// polls, so the tap can be installed as soon as the user flips the switch
/// in System Settings, without relaunching.
@MainActor
@Observable
final class AccessibilityPermission {
    static let shared = AccessibilityPermission()

    private(set) var isTrusted = AXIsProcessTrusted()

    /// Called whenever `isTrusted` changes.
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var isMonitoring = false

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private init() {}

    /// Starts following trust changes: polling while untrusted, and the
    /// system's notification (posted when the Accessibility list changes)
    /// to notice a revocation.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The new state is readable only a moment after the notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refresh()
            }
        }
        updatePolling()
    }

    /// Re-reads the trust state.
    func refresh() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        updatePolling()
        onChange?(trusted)
    }

    /// Asks for trust: the system prompt (which also adds the app to the
    /// Accessibility list) and the Accessibility pane of System Settings,
    /// where the switch is if the prompt was already answered once.
    func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            refresh()
            return
        }
        NSWorkspace.shared.open(Self.settingsURL)
    }

    private func updatePolling() {
        if isTrusted {
            pollTimer?.invalidate()
            pollTimer = nil
        } else if pollTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }
}
