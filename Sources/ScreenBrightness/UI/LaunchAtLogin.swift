import Observation
import OSLog
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for the "Ouvrir au démarrage"
/// toggle. Errors are logged and swallowed; `isEnabled` always reflects the
/// status the system reports afterwards.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = false

    @ObservationIgnored private let logger = Logger(subsystem: "ScreenBrightness", category: "LaunchAtLogin")

    /// Re-reads the registration status (the user may have changed it in
    /// System Settings > General > Login Items).
    func reload() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            logger.error("Could not \(enabled ? "register" : "unregister", privacy: .public) login item: \(error.localizedDescription, privacy: .public)")
        }
        reload()
    }
}
