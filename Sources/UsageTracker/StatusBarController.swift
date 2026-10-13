import SwiftUI
import AppKit

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let showOnboarding = Notification.Name("showOnboarding")
}

/// Brings an app window in front of whatever app is active.
///
/// The app is an LSUIElement accessory, and since macOS 14 `activate(ignoringOtherApps:)` is a
/// request the system may decline, so windows opened from the menu bar landed behind the
/// frontmost app. Becoming a regular app while a window is open makes activation reliable and
/// puts the window in Cmd-Tab; `endPresenting` drops back to menu-bar-only once none are left.
@MainActor
enum WindowPresenter {
    static func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()
    }

    static func endPresenting(_ closing: NSWindow) {
        // Defer: the closing window still reports isVisible during windowWillClose.
        DispatchQueue.main.async {
            // A minimized window is still open; it just isn't visible.
            let anyOpen = NSApp.windows.contains {
                $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.styleMask.contains(.titled)
            }
            if !anyOpen {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
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
        // `window` is non-nil only while the window is open: visible, minimized, or hidden with the app.
        if let existingWindow = window {
            WindowPresenter.present(existingWindow)
            return
        }

        let rootView = SettingsContent(appState: appState)
        let hostingController = NSHostingController(rootView: rootView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.toolbarStyle = .unified
        newWindow.setContentSize(NSSize(
            width: SettingsDesign.windowDefaultWidth,
            height: SettingsDesign.windowDefaultHeight
        ))
        newWindow.minSize = NSSize(
            width: SettingsDesign.windowMinWidth,
            height: SettingsDesign.windowMinHeight
        )
        newWindow.center()
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false
        // Left nil, AppKit focuses the first text field on first display. On a provider page
        // that is the API key field with the whole saved key selected, so one keystroke would
        // replace it. Start with the window itself as first responder instead.
        newWindow.initialFirstResponder = hostingController.view

        self.window = newWindow

        WindowPresenter.present(newWindow)
    }

    func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow { WindowPresenter.endPresenting(closing) }
        window = nil
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
        if let existingWindow = window {
            WindowPresenter.present(existingWindow)
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

        WindowPresenter.present(newWindow)
    }

    func windowWillClose(_ notification: Notification) {
        appState.completeOnboarding()
        if let closing = notification.object as? NSWindow { WindowPresenter.endPresenting(closing) }
        window = nil
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
        popover.contentSize = NSSize(width: 340, height: 400)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOnboardingFromNotification),
            name: .showOnboarding,
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
                    // Self-sizing is enabled lazily at first show: setting
                    // .preferredContentSize during applicationDidFinishLaunching
                    // prevents the NSStatusItem from ever appearing in the menu bar.
                    if let hosting = popover.contentViewController as? NSHostingController<MenuBarView>,
                       hosting.sizingOptions != .preferredContentSize {
                        hosting.sizingOptions = .preferredContentSize
                    }
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

    @objc private func showOnboardingFromNotification() {
        onboardingWindowController?.showOnboarding()
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
