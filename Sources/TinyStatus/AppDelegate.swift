import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
            var items: [NSMenuItem]
        }
        var rows: [Row] = []
        for t in s.tunnels {
            let it = statusRow(
                title: t.title,
                symbol: CheckArt.symbol(icon: t.icon, kind: .tcp, enabled: t.enabled),
                asset: t.image,
                ok: t.enabled && t.up,
                warn: false,
                suffix: !t.enabled ? "off" : t.busy ? "…" : (t.ms.map { String(format: "%.0f ms", $0) } ?? ""),
                disabled: !t.enabled
            )
            var items = [it]
            items.append(statusEnableItem(id: t.id, enabled: t.enabled))
            if t.enabled {
                items.append(contentsOf: statusActionItems(checkId: t.id, actions: t.actions, up: t.up, busy: t.busy))
            }
            rows.append(Row(group: t.group, items: items))
        }
        for d in s.deploys {
            let extra = d.checks.isEmpty ? "" : "\(d.okCount)/\(d.checks.count)"
            let it = statusRow(
                title: d.title,
                symbol: CheckArt.symbol(icon: d.icon, kind: .http, enabled: d.enabled),
                asset: d.image,
                ok: d.enabled && d.health == "healthy",
                warn: d.enabled && d.health == "degraded",
                suffix: !d.enabled ? "off" : extra,
                disabled: !d.enabled
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
            var items = [it]
            items.append(statusEnableItem(id: d.id, enabled: d.enabled))
            if d.enabled {
                items.append(contentsOf: statusActionItems(checkId: d.id, actions: d.actions, up: d.up, busy: false))
            }
            rows.append(Row(group: d.group, items: items))
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
            for k in kids { for item in k.items { m.addItem(item) } }
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

    private func statusActionItems(checkId: String, actions: [CheckAction], up: Bool, busy: Bool) -> [NSMenuItem] {
        let fromRow = actions
        let fromCheck = Store.shared.allChecks().first(where: { $0.id == checkId })?.resolvedActions() ?? []
        let source = fromRow.isEmpty ? fromCheck : fromRow
        return source.filter { $0.isVisible(up: up) }.map { a in
            let it = NSMenuItem(title: a.title, action: #selector(runCheckAction(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = [checkId, a.id]
            it.isEnabled = !busy
            it.indentationLevel = 1
            if let icon = a.icon {
                it.image = NSImage(systemSymbolName: icon, accessibilityDescription: a.title)
                it.image?.isTemplate = true
            }
            return it
        }
    }

    @objc func runCheckAction(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        Store.shared.runAction(checkId: pair[0], actionId: pair[1])
    }

    private func statusEnableItem(id: String, enabled: Bool) -> NSMenuItem {
        let it = NSMenuItem(
            title: enabled ? "Disable" : "Enable",
            action: #selector(toggleCheckEnabled(_:)),
            keyEquivalent: ""
        )
        it.target = self
        it.representedObject = id
        it.indentationLevel = 1
        it.image = NSImage(
            systemSymbolName: enabled ? "pause.circle" : "play.circle",
            accessibilityDescription: enabled ? "Disable" : "Enable"
        )
        it.image?.isTemplate = true
        it.isEnabled = true
        return it
    }

    @objc func toggleCheckEnabled(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let on = Store.shared.allChecks().first(where: { $0.id == id })?.isEnabled ?? true
        Store.shared.setCheckEnabled(id, !on)
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
        title: String, symbol: String?, asset: String?, ok: Bool, warn: Bool, suffix: String,
        disabled: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(showMain), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        let color: NSColor = disabled ? .tertiaryLabelColor : warn ? .systemOrange : ok ? .systemGreen : .systemRed
        let suffixColor: NSColor = disabled ? .tertiaryLabelColor : warn ? .systemOrange : ok ? .secondaryLabelColor : .systemRed
        let text = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 13),
                .foregroundColor: disabled ? NSColor.secondaryLabelColor : NSColor.labelColor,
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
        if let img = CheckArt.nsImage(asset) {
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
        t.displayMode = .iconAndLabel
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
        viewMenu.addItem(.separator())
        let cols = NSMenuItem(title: "Columns", action: nil, keyEquivalent: "")
        let colsMenu = NSMenu()
        colsMenu.delegate = self
        for col in Store.tableColumns {
            let i = NSMenuItem(title: col.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = col.id
            colsMenu.addItem(i)
        }
        cols.submenu = colsMenu
        viewMenu.addItem(cols)
        let filter = NSMenuItem(title: "Filter Status", action: nil, keyEquivalent: "")
        let filterMenu = NSMenu()
        filterMenu.delegate = self
        for (id, title) in [("all", "All"), ("up", "Up"), ("degraded", "Degraded"), ("down", "Down")] {
            let i = NSMenuItem(title: title, action: #selector(setFilter(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = id
            filterMenu.addItem(i)
        }
        filter.submenu = filterMenu
        viewMenu.addItem(filter)
        let group = NSMenuItem(title: "Group By", action: nil, keyEquivalent: "")
        let groupMenu = NSMenu()
        groupMenu.delegate = self
        for (id, title) in [("tag", "Tag"), ("kind", "Kind"), ("none", "None")] {
            let i = NSMenuItem(title: title, action: #selector(setGroupBy(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = id
            groupMenu.addItem(i)
        }
        group.submenu = groupMenu
        viewMenu.addItem(group)
        viewItem.submenu = viewMenu
        menubar.addItem(viewItem)
        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "TinyStatus", action: #selector(showMain), keyEquivalent: "0")
        winItem.submenu = winMenu
        menubar.addItem(winItem)
        NSApp.mainMenu = menubar
    }

    @objc func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let on = Store.shared.hiddenColumns.contains(id)
        Store.shared.columnVisible(id).wrappedValue = on
    }

    @objc func setFilter(_ sender: NSMenuItem) {
        Store.shared.filterStatus = sender.representedObject as? String ?? "all"
        Store.shared.persistTablePrefs()
    }

    @objc func setGroupBy(_ sender: NSMenuItem) {
        Store.shared.editGroupBy = sender.representedObject as? String ?? GroupBy.tag.rawValue
        Store.shared.persistTablePrefs()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items { _ = validateMenuItem(item) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let s = Store.shared
        if menuItem.action == #selector(toggleColumn(_:)), let id = menuItem.representedObject as? String {
            menuItem.state = s.hiddenColumns.contains(id) ? .off : .on
        }
        if menuItem.action == #selector(setFilter(_:)), let id = menuItem.representedObject as? String {
            menuItem.state = s.filterStatus == id ? .on : .off
        }
        if menuItem.action == #selector(setGroupBy(_:)), let id = menuItem.representedObject as? String {
            menuItem.state = s.editGroupBy == id ? .on : .off
        }
        return true
    }
}

final class ToolbarShim: NSObject, NSToolbarDelegate {
    static let shared = ToolbarShim()
    weak var delegate: AppDelegate?
    weak var status: StatusController?

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.search, .filter, .groupBy, .columns, .flexibleSpace, .reload, .settings]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.search, .filter, .groupBy, .columns, .flexibleSpace, .reload, .settings]
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
            i.toolTip = "Filter by name, tag, type, or URL"
            return i
        case .filter:
            let i = NSMenuToolbarItem(itemIdentifier: .filter)
            i.label = "Status"
            i.toolTip = "Filter by status"
            i.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "Filter")
            let m = NSMenu()
            m.delegate = delegate
            for (id, title) in [("all", "All"), ("up", "Up"), ("degraded", "Degraded"), ("down", "Down")] {
                let it = NSMenuItem(title: title, action: #selector(AppDelegate.setFilter(_:)), keyEquivalent: "")
                it.target = delegate
                it.representedObject = id
                m.addItem(it)
            }
            i.menu = m
            return i
        case .groupBy:
            let i = NSMenuToolbarItem(itemIdentifier: .groupBy)
            i.label = "Group"
            i.toolTip = "Group rows by tag, kind, or none"
            i.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Group")
            let m = NSMenu()
            m.delegate = delegate
            for (id, title) in [("tag", "Tag"), ("kind", "Kind"), ("none", "None")] {
                let it = NSMenuItem(title: title, action: #selector(AppDelegate.setGroupBy(_:)), keyEquivalent: "")
                it.target = delegate
                it.representedObject = id
                m.addItem(it)
            }
            i.menu = m
            return i
        case .columns:
            let i = NSMenuToolbarItem(itemIdentifier: .columns)
            i.label = "Columns"
            i.toolTip = "Show or hide columns"
            i.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: "Columns")
            i.menu = status?.columnMenu() ?? NSMenu()
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
    static let filter = NSToolbarItem.Identifier("filter")
    static let columns = NSToolbarItem.Identifier("columns")
    static let groupBy = NSToolbarItem.Identifier("groupBy")
}
