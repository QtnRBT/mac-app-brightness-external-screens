import AppKit
import SwiftUI

/// Root of the menu bar panel: binds `DisplayController` to the pure
/// `DisplayListView` and `PanelFooterView`.
struct MenuContentView: View {
    private let controller: DisplayController
    private let presentation: PanelPresentation
    private let onOpenSettings: () -> Void
    private let keyAccess = AccessibilityPermission.shared

    init(controller: DisplayController, presentation: PanelPresentation, onOpenSettings: @escaping () -> Void) {
        self.controller = controller
        self.presentation = presentation
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        PanelView(
            displays: controller.displays,
            isRefreshing: controller.isRefreshing,
            masterBrightness: controller.masterBrightness,
            needsKeyAccess: !keyAccess.isTrusted,
            onRequestKeyAccess: { keyAccess.request() },
            onOpenSettings: onOpenSettings,
            onChange: { id, value in controller.setBrightness(value, for: id) },
            onMasterChange: { controller.setMasterBrightness($0) },
            onRefresh: { controller.refresh() },
            onQuit: { NSApp.terminate(nil) }
        )
        .panelPresentation(presentation)
        .onAppear {
            // Screens are re-read by `StatusItemController` on every opening.
            keyAccess.refresh()
        }
    }
}

/// Whole panel layout (modules + footer) with injected state; renderable with
/// fake data.
struct PanelView: View {
    let displays: [DisplayItem]
    let isRefreshing: Bool
    let masterBrightness: Double?
    let needsKeyAccess: Bool
    let onRequestKeyAccess: () -> Void
    let onOpenSettings: () -> Void
    let onChange: (CGDirectDisplayID, Double) -> Void
    let onMasterChange: (Double) -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: ModuleMetrics.moduleSpacing) {
            DisplayListView(
                displays: displays,
                isRefreshing: isRefreshing,
                masterBrightness: masterBrightness,
                onChange: onChange,
                onMasterChange: onMasterChange
            )
            PanelFooterView(
                isRefreshing: isRefreshing,
                needsKeyAccess: needsKeyAccess,
                onRequestKeyAccess: onRequestKeyAccess,
                onOpenSettings: onOpenSettings,
                onRefresh: onRefresh,
                onQuit: onQuit
            )
            .padding(.top, 2)
        }
        .padding(ModuleMetrics.panelPadding)
        .frame(width: ModuleMetrics.panelWidth)
    }
}
