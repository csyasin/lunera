import AppKit
import SwiftUI

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = NotchPanelController(
            content: CalendarView(store: calendarStore),
            store: calendarStore,
            onGoToToday: { [weak calendarStore] in calendarStore?.goToToday() },
            onPreferences: { [weak self] in self?.showPreferences() }
        )
        Task { [weak calendarStore] in
            await calendarStore?.requestCalendarAccessIfNeeded()
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
