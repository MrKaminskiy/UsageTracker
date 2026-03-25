import SwiftUI
import AppKit

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

@MainActor
class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func showSettings() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.orderFrontRegardless()
            existingWindow.makeKey()
            return
        }

        let settingsView = SettingsView(appState: appState)
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "UsageTracker Settings"
        newWindow.styleMask = [.titled, .closable]
        newWindow.center()
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Nothing needed - we stay in accessory mode
    }
}

@MainActor
class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func showOnboarding() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.orderFrontRegardless()
            existingWindow.makeKey()
            return
        }

        let onboardingView = OnboardingView {
            self.appState.completeOnboarding()
            self.window?.close()
        }
        let hostingController = NSHostingController(rootView: onboardingView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Welcome to UsageTracker"
        newWindow.styleMask = [.titled, .closable]
        newWindow.center()
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        appState.completeOnboarding()
    }
}

@MainActor
class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var contextMenu: NSMenu!
    private var eventMonitor: Any?
    private var appState: AppState?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    var onClearCache: (() -> Void)?

    func setup(with contentView: some View, appState: AppState) {
        self.appState = appState
        self.settingsWindowController = SettingsWindowController(appState: appState)
        self.onboardingWindowController = OnboardingWindowController(appState: appState)
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
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        contextMenu.addItem(settingsItem)

        let clearCacheItem = NSMenuItem(title: "Clear Cache", action: #selector(clearCache), keyEquivalent: "")
        clearCacheItem.target = self
        clearCacheItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        contextMenu.addItem(clearCacheItem)

        contextMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit UsageTracker", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        contextMenu.addItem(quitItem)

        // Monitor for clicks outside popover to close it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                if self?.popover.isShown == true {
                    self?.popover.performClose(nil)
                }
            }
        }

        // Observe settings notification from gear button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettings,
            object: nil
        )
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
                    Task {
                        await appState?.refresh()
                    }
                }
            }
        }
    }

    @objc private func openSettings() {
        // Close popover first
        if popover.isShown {
            popover.performClose(nil)
        }

        settingsWindowController?.showSettings()
    }

    @objc private func clearCache() {
        onClearCache?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func showOnboarding() {
        onboardingWindowController?.showOnboarding()
    }

    func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
