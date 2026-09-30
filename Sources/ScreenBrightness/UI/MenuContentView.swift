import AppKit
import SwiftUI

/// Root of the `MenuBarExtra` window: binds `DisplayController` to the pure
/// `DisplayListView` and `PanelFooterView`.
struct MenuContentView: View {
    private let controller: DisplayController
    @State private var launchAtLogin = LaunchAtLogin()

    init(controller: DisplayController) {
        self.controller = controller
    }

    var body: some View {
        PanelView(
            displays: controller.displays,
            isRefreshing: controller.isRefreshing,
            launchAtLogin: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.setEnabled($0) }
            ),
            onChange: { id, value in controller.setBrightness(value, for: id) },
            onRefresh: { controller.refresh() },
            onQuit: { NSApp.terminate(nil) }
        )
        .onAppear {
            // Pick up changes made with the monitors' physical buttons.
            controller.refresh()
            launchAtLogin.reload()
        }
    }
}

/// Whole panel layout (modules + footer) with injected state; renderable with
/// fake data.
struct PanelView: View {
    let displays: [DisplayItem]
    let isRefreshing: Bool
    @Binding var launchAtLogin: Bool
    let onChange: (CGDirectDisplayID, Double) -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: ModuleMetrics.moduleSpacing) {
            DisplayListView(displays: displays, isRefreshing: isRefreshing, onChange: onChange)
            PanelFooterView(
                isRefreshing: isRefreshing,
                launchAtLogin: $launchAtLogin,
                onRefresh: onRefresh,
                onQuit: onQuit
            )
            .padding(.top, 2)
        }
        .padding(ModuleMetrics.panelPadding)
        .frame(width: ModuleMetrics.panelWidth)
    }
}
