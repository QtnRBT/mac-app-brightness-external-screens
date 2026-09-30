import SwiftUI

@main
struct ScreenBrightnessApp: App {
    @State private var controller = DisplayController()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: controller)
        } label: {
            Image(systemName: "sun.max.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
