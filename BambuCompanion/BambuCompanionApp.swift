import SwiftUI

@main
struct BambuCompanionApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
