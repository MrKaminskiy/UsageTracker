import SwiftUI
import AppKit

@MainActor
class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var contextMenu: NSMenu!
    private var eventMonitor: Any?
    private weak var appState: AppState?
    var onClearCache: (() -> Void)?

    /// Initializes the status bar UI and click handlers.
    func setup(with contentView: some View, appState: AppState) {
        self.appState = appState
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

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        contextMenu.addItem(settingsItem)

        let clearCacheItem = NSMenuItem(title: "Clear Cache", action: #selector(clearCache), keyEquivalent: "")
        clearCacheItem.target = self
        contextMenu.addItem(clearCacheItem)

        contextMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit UsageTracker", action: #selector(quitApp), keyEquivalent: "")
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
                refreshOnLeftClick()
                if let button = statusItem.button {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    @objc private func openSettings() {
        // Close the popover first
        if popover.isShown {
            popover.performClose(nil)
        }

        // Activate app and open settings
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)

        // Ensure settings window is in front
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                if window.title.contains("Settings") || window.identifier?.rawValue.contains("settings") == true {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }

    @objc private func clearCache() {
        onClearCache?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Triggers a refresh when the status bar icon is clicked.
    private func refreshOnLeftClick() {
        guard let appState = appState, !appState.isLoading else { return }
        Task { @MainActor in
            await appState.refresh()
        }
    }

    func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
