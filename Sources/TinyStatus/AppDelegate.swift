import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var instance: AppDelegate?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.instance = self
        NSApp.setActivationPolicy(.regular)
        Task { @MainActor in self.showMain() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in self.showMain() }
        return true
    }

    @MainActor
    func showMain() {
        NSApp.setActivationPolicy(.regular)
        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = Panel(store: Store.shared)
        let hosting = NSHostingView(rootView: root)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "TinyStatus"
        w.titleVisibility = .visible
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.isOpaque = true
        w.backgroundColor = .windowBackgroundColor
        w.contentView = hosting
        w.setContentSize(NSSize(width: 420, height: 680))
        w.center()
        w.makeKeyAndOrderFront(nil)
        mainWindow = w
        NSApp.activate(ignoringOtherApps: true)
    }
}

