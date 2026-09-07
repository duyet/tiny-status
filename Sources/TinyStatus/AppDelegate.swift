import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var instance: AppDelegate?
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var importWindow: NSWindow?

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
        let s = Store.shared
        let name = s.healthCheckTotal == 0
            ? "ellipsis.circle.fill"
            : ok ? "checkmark.circle.fill" : "xmark.circle.fill"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "TinyStatus")
        img?.isTemplate = true
        statusItem?.button?.image = img
        statusItem?.button?.imagePosition = .imageLeading
        statusItem?.button?.title = s.healthCheckTotal == 0 ? "" : "\(s.healthCheckUp)/\(s.healthCheckTotal)"
        statusItem?.button?.toolTip = s.healthCheckSummary
        rebuildStatusMenu()
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
        w.setContentSize(NSSize(width: 940, height: 500))
        w.minSize = NSSize(width: 720, height: 320)
        w.backgroundColor = .windowBackgroundColor
        w.titlebarAppearsTransparent = false
        ToolbarShim.shared.status = vc
        w.toolbar = makeToolbar()
        w.toolbarStyle = .unified
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        mainWindow = w
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showImport() {
        if importWindow == nil {
            let w = NSWindow(contentViewController: ImportController())
            w.title = "Import checks"
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(NSSize(width: 520, height: 360))
            w.isReleasedWhenClosed = false
            importWindow = w
        }
        importWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings() {
        Store.shared.loadConfigEditor()
        if settingsWindow == nil {
            let host = NSHostingController(rootView: ConfigWindow(store: Store.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "Settings"
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(NSSize(width: 780, height: 540))
            w.toolbarStyle = .unified
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "TinyStatus")
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageLeading
        statusItem = item
        rebuildStatusMenu()
        setStatus(ok: Store.shared.allOK)
    }

    private func rebuildStatusMenu() {
        let s = Store.shared
        let m = NSMenu()
        m.autoenablesItems = false
        let summary = s.healthCheckTotal == 0 ? "No health checks yet" : s.healthCheckSummary
        m.addItem(NSMenuItem.sectionHeader(title: summary))

        struct Row {
            var group: String
            var item: NSMenuItem
        }
        var rows: [Row] = []
        for t in s.tunnels {
            let it = statusRow(
                title: t.title,
                symbol: t.title.lowercased().contains("gitlab") ? nil : "network",
                asset: t.title.lowercased().contains("gitlab") ? "GitLab" : nil,
                ok: t.up,
                warn: false,
                suffix: t.ms.map { String(format: "%.0f ms", $0) } ?? ""
            )
            rows.append(Row(group: t.group, item: it))
        }
        for d in s.deploys {
            let extra = d.checks.isEmpty ? "" : "\(d.okCount)/\(d.checks.count)"
            let it = statusRow(
                title: d.title,
                symbol: "globe",
                asset: nil,
                ok: d.health == "healthy",
                warn: d.health == "degraded",
                suffix: extra
            )
            if !d.checks.isEmpty {
                let sub = NSMenu()
                sub.autoenablesItems = false
                for c in d.checks {
                    sub.addItem(statusRow(
                        title: c.name,
                        symbol: serviceSymbol(c.name),
                        asset: nil,
                        ok: c.status == "healthy",
                        warn: c.status == "degraded",
                        suffix: c.ms.map { String(format: "%.0f ms", $0) } ?? ""
                    ))
                }
                it.submenu = sub
            }
            rows.append(Row(group: d.group, item: it))
        }
        let pref = s.groupOrder
        let names = pref.filter { g in rows.contains { $0.group == g } }
            + Array(Set(rows.map(\.group)).subtracting(pref)).sorted()
        for (i, g) in names.enumerated() {
            let kids = rows.filter { $0.group == g }
            guard !kids.isEmpty else { continue }
            if names.count > 1 {
                if i > 0 { m.addItem(.separator()) }
                m.addItem(NSMenuItem.sectionHeader(title: g))
            }
            for k in kids { m.addItem(k.item) }
        }

        m.addItem(.separator())
        m.addItem(actionRow("Open TinyStatus", "macwindow", #selector(showMain), ""))
        m.addItem(actionRow("Reload", "arrow.clockwise", #selector(reload(_:)), "r"))
        m.addItem(actionRow("Import checks…", "plus.circle", #selector(showImport), "i"))
        m.addItem(actionRow("Settings…", "gearshape", #selector(showSettings), ","))
        m.addItem(.separator())
        let quit = actionRow("Quit TinyStatus", "power", #selector(NSApplication.terminate(_:)), "q")
        quit.target = NSApp
        m.addItem(quit)
        statusItem?.menu = m
    }

    private func actionRow(_ title: String, _ symbol: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        i.isEnabled = true
        i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        i.image?.isTemplate = true
        return i
    }

    private func serviceSymbol(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("postgres") || n.contains("data") { return "cylinder.split.1x2" }
        if n.contains("redis") || n.contains("cache") { return "bolt.fill" }
        if n.contains("qdrant") || n.contains("vector") { return "square.stack.3d.up" }
        if n.contains("click") { return "chart.bar.fill" }
        if n.contains("openrouter") || n.contains("llm") { return "sparkles" }
        if n.contains("api") { return "point.3.connected.trianglepath.dotted" }
        if n.contains("migrat") { return "arrow.triangle.2.circlepath" }
        if n.contains("cube") { return "cube.fill" }
        return "circle.fill"
    }

    private func statusRow(
        title: String, symbol: String?, asset: String?, ok: Bool, warn: Bool, suffix: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(showMain), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        let color: NSColor = warn ? .systemOrange : ok ? .systemGreen : .systemRed
        let suffixColor: NSColor = warn ? .systemOrange : ok ? .secondaryLabelColor : .systemRed
        let text = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        if !suffix.isEmpty {
            text.append(NSAttributedString(
                string: "    \(suffix)",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: suffixColor,
                ]
            ))
        }
        item.attributedTitle = text
        if let asset,
           let url = Bundle.main.url(forResource: asset, withExtension: "png"),
           let img = NSImage(contentsOf: url)
        {
            img.size = NSSize(width: 16, height: 16)
            item.image = img
        } else if let symbol {
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            item.image = img?.withSymbolConfiguration(cfg)
            item.image?.isTemplate = false
        }
        return item
    }

    private func makeToolbar() -> NSToolbar {
        let t = NSToolbar(identifier: "TinyStatus")
        t.displayMode = .iconOnly
        t.allowsUserCustomization = false
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
        appMenu.addItem(withTitle: "Import checks…", action: #selector(showImport), keyEquivalent: "i")
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
    weak var status: StatusController?

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.search, .flexibleSpace, .reload, .settings]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.search, .flexibleSpace, .reload, .settings]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .search:
            let i = NSSearchToolbarItem(itemIdentifier: .search)
            if let f = status?.search { i.searchField = f }
            i.toolTip = "Filter checks"
            return i
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
    static let search = NSToolbarItem.Identifier("search")
}
