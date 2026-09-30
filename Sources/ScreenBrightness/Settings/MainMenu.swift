import AppKit

/// The app's menu bar menus. They show only while the app is `.regular`
/// (settings window open), but their key equivalents also serve that window:
/// without them ⌘W would not close it.
enum MainMenu {
    static func make(settings: SettingsWindowController) -> NSMenu {
        let appName = "Screen Brightness"
        let main = NSMenu()

        let app = NSMenu(title: appName)
        app.addItem(withTitle: "À propos de \(appName)",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settingsItem = app.addItem(withTitle: "Réglages…",
                                       action: #selector(SettingsWindowController.showWindow(_:)), keyEquivalent: ",")
        settingsItem.target = settings
        app.addItem(.separator())
        app.addItem(withTitle: "Masquer \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Masquer les autres",
                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Tout afficher",
                    action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quitter \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app))

        let window = NSMenu(title: "Fenêtre")
        window.addItem(withTitle: "Placer dans le Dock",
                       action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Fermer", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(window))
        NSApp.windowsMenu = window

        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
