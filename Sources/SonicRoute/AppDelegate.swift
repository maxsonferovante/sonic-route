import AppKit
import SwiftUI
import SonicRouteCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var viewModel: MenuBarViewModel?
    private var shortcutService: CarbonGlobalShortcutService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let shortcutService = CarbonGlobalShortcutService()
        let viewModel = MenuBarViewModel(globalShortcutService: shortcutService)
        self.shortcutService = shortcutService
        self.viewModel = viewModel

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 390, height: 500)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanelView(viewModel: viewModel)
        )
        self.popover = popover

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sonic Route")
            button.image?.isTemplate = true
            button.toolTip = "Sonic Route — controle de áudio por app"
            button.setAccessibilityLabel("Sonic Route")
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        self.statusItem = statusItem

        shortcutService.onShortcutPressed = { [weak self] in
            self?.togglePopover(nil)
        }

        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stop()
        try? shortcutService?.setEnabled(false)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
