import CoreGraphics
import SwiftUI

/// Pure list of screen modules. No dependency on `DisplayController`, so it
/// can be rendered with fake data (previews, snapshot harnesses).
struct DisplayListView: View {
    let displays: [DisplayItem]
    let isRefreshing: Bool
    let onChange: (CGDirectDisplayID, Double) -> Void

    init(
        displays: [DisplayItem],
        isRefreshing: Bool = false,
        onChange: @escaping (CGDirectDisplayID, Double) -> Void
    ) {
        self.displays = displays
        self.isRefreshing = isRefreshing
        self.onChange = onChange
    }

    var body: some View {
        if displays.isEmpty {
            emptyState
        } else {
            modules
        }
    }

    @ViewBuilder
    private var modules: some View {
        let stack = VStack(spacing: ModuleMetrics.moduleSpacing) {
            ForEach(displays) { display in
                DisplayModuleView(display: display) { value in
                    onChange(display.id, value)
                }
            }
        }
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) { stack }
        } else {
            stack
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Recherche des écrans…")
            } else {
                Image(systemName: "display.trianglebadge.exclamationmark")
                Text("Aucun écran détecté")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 64)
        .moduleBackground()
    }
}
