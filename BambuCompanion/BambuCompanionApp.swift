import AppKit
import SwiftUI

@main
struct BambuCompanionApp: App {
    @StateObject private var appState = AppState()
    private let shouldOpenMenuAtLaunch: Bool

    init() {
        shouldOpenMenuAtLaunch = UserDefaults.standard.bool(
            forKey: VideoDefaultsKey.pictureInPictureEnabled
        )
    }

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
                MenuBarExtraAutoOpener(shouldOpen: shouldOpenMenuAtLaunch)
                    .frame(width: 0, height: 0)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

private struct MenuBarExtraAutoOpener: NSViewRepresentable {
    let shouldOpen: Bool

    func makeNSView(context: Context) -> AutoOpenView {
        let view = AutoOpenView()
        view.shouldOpen = shouldOpen
        return view
    }

    func updateNSView(_ view: AutoOpenView, context: Context) {
        // The launch preference is intentionally captured once in App.init().
    }

    final class AutoOpenView: NSView {
        var shouldOpen = false

        private var didOpen = false
        private var attemptCount = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleOpenIfNeeded()
        }

        private func scheduleOpenIfNeeded() {
            guard shouldOpen, !didOpen, attemptCount < 20, window != nil else {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.openMenuBarExtra()
            }
        }

        private func openMenuBarExtra() {
            guard shouldOpen, !didOpen else {
                return
            }
            var ancestor = superview
            while let view = ancestor {
                if let button = view as? NSStatusBarButton {
                    didOpen = true
                    button.performClick(nil)
                    return
                }
                ancestor = view.superview
            }
            attemptCount += 1
            scheduleOpenIfNeeded()
        }
    }
}
