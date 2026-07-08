import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appModel: AppModel?
    private var settingsCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            await appModel?.bootstrap()
        }
    }

    // Called when the user clicks the app in the Applications folder / Finder while
    // it is already running. As a menu-bar agent (LSUIElement) there is no Dock icon
    // and no window to reopen, so a click would otherwise do nothing. Surface the app
    // by activating it and showing Settings so the click has a visible effect.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showSettings(openSettings: {})
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func showSettings(openSettings: @escaping () -> Void) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()

        DispatchQueue.main.async { [weak self] in
            self?.bringSettingsToFront(retryCount: 3)
        }
    }

    private func bringSettingsToFront(retryCount: Int) {
        orderMenuBarPanelBack()

        if let settingsWindow = settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            settingsWindow.orderFrontRegardless()
            observeSettingsWindowClosed(settingsWindow)
            return
        }

        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        if retryCount > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.bringSettingsToFront(retryCount: retryCount - 1)
            }
        }
    }

    private var settingsWindow: NSWindow? {
        NSApp.windows.first { window in
            !isMenuBarPanel(window) && isSettingsWindow(window)
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        let typeName = String(describing: type(of: window))
        if typeName.contains("Settings") { return true }
        if window.title.localizedCaseInsensitiveContains("Settings") { return true }
        return window.identifier?.rawValue.localizedCaseInsensitiveContains("Settings") == true
    }

    private func isMenuBarPanel(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("StatusBar")
    }

    private func orderMenuBarPanelBack() {
        for window in NSApp.windows where isMenuBarPanel(window) {
            window.orderBack(nil)
        }
    }

    private func observeSettingsWindowClosed(_ window: NSWindow) {
        if let settingsCloseObserver {
            NotificationCenter.default.removeObserver(settingsCloseObserver)
        }
        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            if let settingsCloseObserver = self?.settingsCloseObserver {
                NotificationCenter.default.removeObserver(settingsCloseObserver)
                self?.settingsCloseObserver = nil
            }
        }
    }
}
