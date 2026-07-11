import SwiftUI

@main
struct BambuCompanionApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.menuBarSymbolName)
                if let progress = appState.menuBarProgressTitle {
                    Text(progress)
                        .monospacedDigit()
                }
            }
            .background {
                PictureInPictureStartupView(url: appState.videoStreamURL)
                    .frame(width: 160, height: 90)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
