import SwiftUI
import AppKit

@MainActor
class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var contextMenu: NSMenu!
    private var eventMonitor: Any?

    func setup(with contentView: some View) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover for main content
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Create right-click context menu
        contextMenu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        contextMenu.addItem(settingsItem)

        contextMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit UsageTracker", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)

        // Monitor for clicks outside popover to close it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                if self?.popover.isShown == true {
                    self?.popover.performClose(nil)
                }
            }
        }
    }

    func updateIcon(percentage: Double, isLoading: Bool) {
        guard let button = statusItem.button else { return }

        let icon = NSHostingView(rootView: MenuBarIcon(percentage: percentage, isLoading: isLoading))
        icon.frame = NSRect(x: 0, y: 0, width: 22, height: 22)

        button.subviews.forEach { $0.removeFromSuperview() }
        button.addSubview(icon)
        button.frame = icon.frame
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right click - show context menu
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // Left click - toggle popover
            if popover.isShown {
                popover.performClose(nil)
            } else {
                if let button = statusItem.button {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
