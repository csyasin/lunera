import AppKit
import CoreServices
import SwiftUI

enum LuneraLink {
    static let scheme = "lunera"
    static let openAction = "open"
    static let openPanelURL = "\(scheme)://\(openAction)"

    static func opensPanel(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == openAction
            && (url.path.isEmpty || url.path == "/")
            && url.user == nil && url.password == nil && url.port == nil
            && url.query == nil && url.fragment == nil
    }
}

@main
struct LuneraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var preferencesWindow: NSWindowController?
    private let calendarStore = CalendarStore()
    private let updater = AppUpdater()
    private var pendingPanelOpen = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register before launch completes so URL events also work without a
        // SwiftUI content window, including a cold launch of this menu-bar app.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleOpenURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = NotchPanelController(
            content: CalendarView(store: calendarStore),
            store: calendarStore,
            onGoToToday: { [weak calendarStore] in calendarStore?.goToToday() },
            onPreferences: { [weak self] in self?.showPreferences() },
            canCheckForUpdates: { [weak self] in self?.updater.canCheckForUpdates ?? false },
            onCheckForUpdates: { [weak self] in self?.updater.checkForUpdates() }
        )
        if pendingPanelOpen {
            pendingPanelOpen = false
            panelController?.show()
        }
        Task { [weak calendarStore] in
            await calendarStore?.requestCalendarAccessIfNeeded()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openPanel(for: urls)
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: value) else { return }
        openPanel(for: [url])
    }

    private func openPanel(for urls: [URL]) {
        guard urls.contains(where: LuneraLink.opensPanel) else { return }
        if let panelController {
            panelController.show()
        } else {
            // macOS may deliver the URL before the panel has been constructed.
            pendingPanelOpen = true
        }
    }

    private func showPreferences() {
        panelController?.hide(animated: false)
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView(updater: updater)))
            window.title = "Lunera 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = NSWindowController(window: window)
        }
        preferencesWindow?.showWindow(nil)
        preferencesWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
