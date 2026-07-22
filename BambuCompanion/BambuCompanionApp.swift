import AppKit
import Combine
import Sparkle
import SwiftUI

@main
struct BambuCompanionApp: App {
    @NSApplicationDelegateAdaptor(BambuCompanionAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

@MainActor
private final class BambuCompanionAppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var appStateObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()

        appStateObserver = appState.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }

        if UserDefaults.standard.bool(forKey: VideoDefaultsKey.pictureInPictureEnabled) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showPopover()
            }
        }
    }

    private func configurePopover() {
        let panel = MenuPanelView(
            updater: updaterController.updater,
            onPreferredContentHeightChange: { [weak self] height in
                self?.setPopoverHeight(height)
            }
        )
        .environmentObject(appState)

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 372, height: 528)
        popover.contentViewController = TopAlignedHostingViewController(
            rootView: AnyView(panel)
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageLeading
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            return
        }
        let image = NSImage(
            systemSymbolName: appState.menuBarSymbolName,
            accessibilityDescription: nil
        )
        image?.isTemplate = true
        button.image = image
        button.title = appState.menuBarProgressTitle.map { " \($0)" } ?? ""
    }

    private func setPopoverHeight(_ height: CGFloat) {
        guard height > 0, abs(popover.contentSize.height - height) > 0.5 else {
            return
        }
        popover.contentSize = NSSize(width: 372, height: height)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else {
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

@MainActor
private final class TopAlignedHostingViewController: NSViewController {
    private let hostingController: NSHostingController<AnyView>

    init(rootView: AnyView) {
        hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let containerView = NSView()
        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.setContentHuggingPriority(.required, for: .vertical)
        hostedView.setContentCompressionResistancePriority(.required, for: .vertical)

        addChild(hostingController)
        containerView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostedView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
        view = containerView
    }
}
