import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var instance: AppDelegate?
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.instance = self
        buildMenu()
        setupStatusItem()
        showMain()
        Store.shared.poll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return true
    }

    func setStatus(ok: Bool) {
        let name = ok ? "checkmark.circle.fill" : "xmark.circle.fill"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "TinyStatus")
        statusItem?.button?.toolTip = ok ? "All checks OK" : "Something is down"
    }

    @objc func showMain() {
        NSApp.setActivationPolicy(.regular)
        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let vc = StatusController()
        let w = NSWindow(contentViewController: vc)
        w.title = "TinyStatus"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 720, height: 520))
        w.minSize = NSSize(width: 560, height: 360)
        w.toolbar = makeToolbar()
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        mainWindow = w
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings() {
        Store.shared.loadConfigEditor()
        if settingsWindow == nil {
            let host = NSHostingController(rootView: ConfigWindow(store: Store.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "Settings"
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(NSSize(width: 560, height: 520))
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func reload(_ sender: Any?) {
        Store.shared.load()
        Store.shared.poll()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "TinyStatus")
        item.button?.action = #selector(showMain)
        item.button?.target = self
        statusItem = item
        setStatus(ok: Store.shared.allOK)
    }

    private func makeToolbar() -> NSToolbar {
        let t = NSToolbar(identifier: "TinyStatus")
        t.displayMode = .iconAndLabel
        t.delegate = ToolbarShim.shared
        ToolbarShim.shared.delegate = self
        return t
    }

    private func buildMenu() {
        let menubar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About TinyStatus", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit TinyStatus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menubar.addItem(appItem)
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Reload", action: #selector(reload(_:)), keyEquivalent: "r")
        viewItem.submenu = viewMenu
        menubar.addItem(viewItem)
        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "TinyStatus", action: #selector(showMain), keyEquivalent: "0")
        winItem.submenu = winMenu
        menubar.addItem(winItem)
        NSApp.mainMenu = menubar
    }
}

final class ToolbarShim: NSObject, NSToolbarDelegate {
    static let shared = ToolbarShim()
    weak var delegate: AppDelegate?

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.reload, .settings, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .reload, .settings]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .reload:
            let i = NSToolbarItem(itemIdentifier: .reload)
            i.label = "Reload"
            i.paletteLabel = "Reload"
            i.toolTip = "Poll tunnels and health now"
            i.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
            i.action = #selector(AppDelegate.reload(_:))
            i.target = delegate
            return i
        case .settings:
            let i = NSToolbarItem(itemIdentifier: .settings)
            i.label = "Settings"
            i.paletteLabel = "Settings"
            i.toolTip = "Open settings"
            i.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
            i.action = #selector(AppDelegate.showSettings)
            i.target = delegate
            return i
        default:
            return nil
        }
    }
}

extension NSToolbarItem.Identifier {
    static let reload = NSToolbarItem.Identifier("reload")
    static let settings = NSToolbarItem.Identifier("settings")
}
