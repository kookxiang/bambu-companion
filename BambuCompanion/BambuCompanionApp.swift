import AppKit
import Sparkle
import SwiftUI

@main
struct BambuCompanionApp: App {
    @StateObject private var appState = AppState()
    private let updaterController: SPUStandardUpdaterController
    private let shouldOpenMenuAtLaunch: Bool

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        shouldOpenMenuAtLaunch = UserDefaults.standard.bool(
            forKey: VideoDefaultsKey.pictureInPictureEnabled
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(updater: updaterController.updater)
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

            if let contentView = window?.contentView,
               let button = findStatusBarButton(in: contentView) {
                didOpen = true
                button.performClick(nil)
                return
            }

            if let window, let contentView = window.contentView {
                didOpen = true
                let location = contentView.convert(
                    NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY),
                    to: nil
                )
                sendMouseEvent(.leftMouseDown, at: location, to: window)
                sendMouseEvent(.leftMouseUp, at: location, to: window)
                return
            }

            attemptCount += 1
            scheduleOpenIfNeeded()
        }

        private func findStatusBarButton(in view: NSView) -> NSStatusBarButton? {
            if let button = view as? NSStatusBarButton {
                return button
            }
            for subview in view.subviews {
                if let button = findStatusBarButton(in: subview) {
                    return button
                }
            }
            return nil
        }

        private func sendMouseEvent(_ type: NSEvent.EventType, at location: NSPoint, to window: NSWindow) {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ) else {
                return
            }
            window.sendEvent(event)
        }
    }
}
