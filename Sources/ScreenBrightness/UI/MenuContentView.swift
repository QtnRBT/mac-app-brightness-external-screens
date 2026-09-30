import AppKit
import SwiftUI

/// Root of the menu bar panel: binds `DisplayController` to the pure
/// `DisplayListView` and `PanelFooterView`.
struct MenuContentView: View {
    private let controller: DisplayController
    private let presentation: PanelPresentation
    @State private var launchAtLogin = LaunchAtLogin()
    private let keyPreferences = BrightnessKeyPreferences.shared
    private let keyAccess = AccessibilityPermission.shared

    init(controller: DisplayController, presentation: PanelPresentation) {
        self.controller = controller
        self.presentation = presentation
    }

    var body: some View {
        PanelView(
            displays: controller.displays,
            isRefreshing: controller.isRefreshing,
            launchAtLogin: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ),
            functionKeys: Binding(
                get: { keyPreferences.functionKeysEnabled },
                set: { keyPreferences.functionKeysEnabled = $0 }
            ),
            needsKeyAccess: !keyAccess.isTrusted,
            onRequestKeyAccess: { keyAccess.request() },
            onChange: { id, value in controller.setBrightness(value, for: id) },
            onRefresh: { controller.refresh() },
            onQuit: { NSApp.terminate(nil) }
        )
        .panelPresentation(presentation)
        .onAppear {
            // The user may have changed it in System Settings > Login Items.
            // (Screens are re-read by `StatusItemController` on every opening.)
            launchAtLogin.reload()
            keyAccess.refresh()
        }
    }
}

/// Whole panel layout (modules + footer) with injected state; renderable with
/// fake data.
struct PanelView: View {
    let displays: [DisplayItem]
    let isRefreshing: Bool
    @Binding var launchAtLogin: Bool
    @Binding var functionKeys: Bool
    let needsKeyAccess: Bool
    let onRequestKeyAccess: () -> Void
    let onChange: (CGDirectDisplayID, Double) -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: ModuleMetrics.moduleSpacing) {
            DisplayListView(displays: displays, isRefreshing: isRefreshing, onChange: onChange)
            PanelFooterView(
                isRefreshing: isRefreshing,
                launchAtLogin: $launchAtLogin,
                functionKeys: $functionKeys,
                needsKeyAccess: needsKeyAccess,
                onRequestKeyAccess: onRequestKeyAccess,
                onRefresh: onRefresh,
                onQuit: onQuit
            )
            .padding(.top, 2)
        }
        .padding(ModuleMetrics.panelPadding)
        .frame(width: ModuleMetrics.panelWidth)
    }
}
