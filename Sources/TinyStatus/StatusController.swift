import AppKit
import Combine

private enum Col: String, CaseIterable {
    case status, name, kind, tags, group, history, latency, version, target, actions

    var title: String {
        switch self {
        case .status: ""
        case .name: "Check"
        case .kind: "Type"
        case .tags: "Tags"
        case .group: "Group"
        case .history: "History"
        case .latency: "Latency"
        case .version: "Version"
        case .target: "Target"
        case .actions: "Actions"
        }
    }

    var optional: Bool {
        self != .status && self != .name
    }
}

enum TableDensity {
    static func rowSize(_ compact: Bool) -> NSTableView.RowSizeStyle { compact ? .small : .large }
    static func indent(_ compact: Bool) -> CGFloat { compact ? 11 : 22 }
    static func spacing(_ compact: Bool) -> NSSize {
        compact ? NSSize(width: 4, height: 0) : NSSize(width: 12, height: 6)
    }
    static func icon(_ compact: Bool) -> CGFloat { compact ? 16 : 22 }
    static func symbol(_ compact: Bool) -> CGFloat { compact ? 14 : 17 }
    static func nameFont(_ compact: Bool, group: Bool, info: Bool) -> NSFont {
        if info { return .systemFont(ofSize: compact ? 12 : 13) }
        if group { return .systemFont(ofSize: compact ? 13 : 15, weight: .semibold) }
        return .systemFont(ofSize: compact ? 13 : 14)
    }
    static func statusColumn(_ compact: Bool) -> CGFloat { compact ? 32 : 44 }
    static func historyHeight(_ compact: Bool) -> CGFloat { compact ? 10 : 18 }
    static func historySlots(_ compact: Bool) -> Int { compact ? 24 : 28 }
}

final class Node: NSObject {
    let id: String
    let title: String
    let kind: String
    let status: String
    let ok: Bool
    let warn: Bool
    let spark: [Double]
    let latency: String
    let target: String
    let url: String?
    let leaf: Bool
    let tags: [String]
    let group: String
    let version: String
    let actions: [CheckAction]
    let enabled: Bool
    let icon: String?
    let image: String?
    var children: [Node] = []

    init(
        id: String, title: String, kind: String, status: String, ok: Bool, warn: Bool,
        spark: [Double], latency: String, target: String, url: String?, leaf: Bool,
        tags: [String] = [], group: String = "", version: String = "",
        actions: [CheckAction] = [],
        enabled: Bool = true,
        icon: String? = nil,
        image: String? = nil,
        children: [Node] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.ok = ok
        self.warn = warn
        self.spark = spark
        self.latency = latency
        self.target = target
        self.url = url
        self.leaf = leaf
        self.tags = tags
        self.group = group
        self.version = version
        self.actions = actions
        self.enabled = enabled
        self.icon = icon
        self.image = image
        self.children = children
    }
}

final class StatusController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    let search = NSSearchField()
    private let store = Store.shared
    private var bag = Set<AnyCancellable>()
    private var roots: [Node] = []
    private var filter = ""
    private var expanded = Set<String>()
    private var seededGroups = false
    private var fitting = false
    private var userResized = false
    private var dragging = false
    private let table = NSOutlineView()
    private let empty = NSTextField(wrappingLabelWithString: "No checks yet. Choose TinyStatus → Import checks…")
    private let progress = NSProgressIndicator()
    private let scroll = NSScrollView()
    private var lastScope = MainState.shared.scope
    private var restoring = false

    override func loadView() {
        search.placeholderString = "Filter"
        search.delegate = self
        search.sendsWholeSearchString = false

        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]

        table.delegate = self
        table.dataSource = self
        table.rowSizeStyle = TableDensity.rowSize(Store.shared.compact)
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.registerForDraggedTypes([.string])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        table.gridStyleMask = []
        table.intercellSpacing = TableDensity.spacing(Store.shared.compact)
        table.indentationPerLevel = TableDensity.indent(Store.shared.compact)
        table.indentationMarkerFollowsCell = true
        table.autoresizesOutlineColumn = false
        table.action = #selector(clicked)
        table.doubleAction = #selector(openRow)
        table.target = self
        table.autosaveName = "TinyStatus.checks.v6"
        table.autosaveTableColumns = true
        let ctx = NSMenu()
        ctx.delegate = self
        table.menu = ctx

        addCol(.status, 44, min: 32, max: 52, flex: false)
        addCol(.name, 240, min: 140, max: 640, flex: true)
        addCol(.actions, 44, min: 36, max: 72, flex: false)
        addCol(.kind, 64, min: 52, max: 110, flex: false)
        addCol(.tags, 96, min: 64, max: 360, flex: false)
        addCol(.group, 72, min: 48, max: 160, flex: false)
        addCol(.history, 148, min: 100, max: 280, flex: true)
        addCol(.latency, 64, min: 48, max: 110, flex: false)
        addCol(.version, 88, min: 56, max: 220, flex: false)
        addCol(.target, 200, min: 80, max: 4000, flex: true)
        table.outlineTableColumn = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(Col.name.rawValue))
        applyHiddenColumns()
        table.headerView?.menu = columnMenu()
        scroll.documentView = table

        empty.font = .systemFont(ofSize: 13)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.isHidden = true
        empty.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 480))
        scroll.translatesAutoresizingMaskIntoConstraints = false
        progress.style = .bar
        progress.controlSize = .mini
        progress.isIndeterminate = true
        progress.isHidden = true
        progress.wantsLayer = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        root.addSubview(empty)
        root.addSubview(progress)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            progress.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 4),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
        ])
        view = root
    }

    private func addCol(_ id: Col, _ w: CGFloat, min: CGFloat, max: CGFloat, flex: Bool) {
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.rawValue))
        c.title = id.title
        c.width = w
        c.minWidth = min
        c.maxWidth = max
        c.resizingMask = flex ? [.userResizingMask, .autoresizingMask] : [.userResizingMask]
        if id != .actions {
            c.sortDescriptorPrototype = NSSortDescriptor(key: id.rawValue, ascending: true)
        }
        table.addTableColumn(c)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.reload()
        }.store(in: &bag)
        MainState.shared.$scope.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.reload()
        }.store(in: &bag)
        NotificationCenter.default.publisher(for: TunnelLifecycle.didChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &bag)
        PollProgress.shared.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshProgress()
        }.store(in: &bag)
        reload()
    }

    func controlTextDidChange(_ obj: Notification) {
        filter = search.stringValue.lowercased()
        reload()
    }

    func reload() {
        applyDensity()
        applyHiddenColumns()
        if store.sortKey.isEmpty {
            table.sortDescriptors = []
        } else {
            let cur = table.sortDescriptors.first
            if cur?.key != store.sortKey || cur?.ascending != store.sortAscending {
                table.sortDescriptors = [NSSortDescriptor(key: store.sortKey, ascending: store.sortAscending)]
            }
        }
        store.persistTablePrefs()
        let keep = expandedIds()
        let ui = MainState.shared
        let byId = Dictionary(store.allChecks().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func inScope(_ id: String) -> Bool {
            guard let c = byId[id] else { return true }
            return ui.scope.matches(c, attention: ui.attention(id))
        }
        var items: [Node] = []
        for t in store.tunnels where inScope(t.id) {
            let n = tunnelNode(t)
            if matches(n) { items.append(n) }
        }
        for d in store.deploys where inScope(d.id) {
            let n = deployNode(d)
            if matches(n) { items.append(n) }
        }
        roots = sortNodes(grouped(items))
        empty.isHidden = !items.isEmpty
        if ui.scope != lastScope {
            lastScope = ui.scope
            if !Motion.reduce, let layer = scroll.layer ?? { scroll.wantsLayer = true; return scroll.layer }() {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.18
                layer.add(fade, forKey: "scope-fade")
            }
        }
        restoring = true
        table.reloadData()
        restoreExpanded(keep)
        restoreSelection()
        restoring = false
        sizeColumnsToContent()
        view.window?.subtitle = items.isEmpty ? "" : "\(store.healthCheckSummary) · \(store.lastCheckedLabel)"
        AppDelegate.instance?.setStatus(ok: store.allOK)
    }

    private func restoreSelection() {
        guard let id = MainState.shared.selectedId else { return }
        for r in 0 ..< table.numberOfRows where (table.item(atRow: r) as? Node)?.id == id {
            table.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            return
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !restoring else { return }
        var id: String?
        if let n = table.item(atRow: table.selectedRow) as? Node, n.kind != "group" {
            var item: Any? = n
            while let cur = item as? Node, cur.kind == "info" || cur.kind == "check" {
                item = table.parent(forItem: cur)
            }
            id = (item as? Node)?.id
        }
        if MainState.shared.selectedId != id { MainState.shared.selectedId = id }
    }

    private func refreshProgress() {
        let p = PollProgress.shared
        if p.total > 0, p.done < p.total {
            progress.layer?.removeAllAnimations()
            progress.alphaValue = 1
            progress.isHidden = false
            if p.done == 0 {
                progress.isIndeterminate = true
                progress.startAnimation(nil)
            } else {
                progress.stopAnimation(nil)
                progress.isIndeterminate = false
                progress.maxValue = Double(p.total)
                progress.doubleValue = Double(p.done)
            }
        } else if !progress.isHidden {
            progress.stopAnimation(nil)
            progress.isIndeterminate = false
            progress.doubleValue = progress.maxValue
            if Motion.reduce {
                progress.isHidden = true
            } else {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
                    progress.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        if PollProgress.shared.done >= PollProgress.shared.total { self?.progress.isHidden = true }
                    }
                })
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if !userResized { table.sizeLastColumnToFit() }
    }

    func outlineViewColumnDidResize(_ notification: Notification) {
        if !fitting { userResized = true }
    }

    func columnMenu() -> NSMenu {
        let m = NSMenu(title: "Columns")
        for col in Col.allCases where col.optional {
            let i = NSMenuItem(title: col.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = col.rawValue
            i.state = store.hiddenColumns.contains(col.rawValue) ? .off : .on
            m.addItem(i)
        }
        m.addItem(.separator())
        let fit = NSMenuItem(title: "Fit to Content", action: #selector(fitColumns), keyEquivalent: "")
        fit.target = self
        m.addItem(fit)
        return m
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let show = store.hiddenColumns.contains(raw)
        store.columnVisible(raw).wrappedValue = show
        userResized = false
        applyHiddenColumns()
        sizeColumnsToContent()
        table.headerView?.menu = columnMenu()
    }

    @objc private func fitColumns() {
        userResized = false
        sizeColumnsToContent()
    }

    private func applyHiddenColumns() {
        let hidden = store.hiddenColumns
        for col in Col.allCases where col.optional {
            table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(col.rawValue))?.isHidden = hidden.contains(col.rawValue)
        }
    }

    private func sizeColumnsToContent() {
        fitting = true
        defer { fitting = false }
        let compact = store.compact
        let body = TableDensity.nameFont(compact, group: false, info: false)
        let small = NSFont.systemFont(ofSize: compact ? 12 : 13)
        let tagsFont = NSFont.systemFont(ofSize: compact ? 11 : 12)
        let header = NSFont.systemFont(ofSize: compact ? 11 : 12, weight: .medium)
        func textW(_ s: String, _ font: NSFont) -> CGFloat {
            ceil((s as NSString).size(withAttributes: [.font: font]).width)
        }
        var nameW: CGFloat = textW("Check", header) + 24
        var kindW: CGFloat = textW("Type", header) + 20
        var tagsW: CGFloat = textW("Tags", header) + 20
        var groupW: CGFloat = textW("Group", header) + 20
        var latW: CGFloat = textW("Latency", header) + 20
        var verW: CGFloat = textW("Version", header) + 20
        func walk(_ nodes: [Node], level: Int) {
            for n in nodes {
                nameW = max(nameW, 28 + CGFloat(level) * table.indentationPerLevel + TableDensity.icon(compact) + 10 + textW(n.title, n.kind == "group" ? TableDensity.nameFont(compact, group: true, info: false) : body) + 16)
                if n.kind != "info" && n.kind != "group" {
                    kindW = max(kindW, textW(n.kind, tagsFont) + 24)
                }
                if !n.tags.isEmpty, n.kind != "group", n.kind != "info" {
                    let chips = n.tags.reduce(CGFloat(0)) { $0 + textW($1, tagsFont) + 16 }
                    tagsW = max(tagsW, chips + CGFloat(max(0, n.tags.count - 1)) * 4 + 12)
                }
                if !n.group.isEmpty, n.kind != "group", n.kind != "info" {
                    groupW = max(groupW, textW(n.group, small) + 20)
                }
                if !n.latency.isEmpty {
                    latW = max(latW, textW(n.latency, .monospacedDigitSystemFont(ofSize: 12, weight: .regular)) + 20)
                }
                if !n.version.isEmpty {
                    verW = max(verW, textW(n.version, small) + 20)
                }
                walk(n.children, level: level + 1)
            }
        }
        walk(roots, level: 0)
        applyHiddenColumns()
        if userResized { return }
        func set(_ id: Col, _ w: CGFloat) {
            guard let c = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id.rawValue)), !c.isHidden else { return }
            c.width = min(c.maxWidth, max(c.minWidth, w))
        }
        set(.status, TableDensity.statusColumn(store.compact))
        set(.name, nameW)
        set(.actions, 44)
        set(.kind, kindW)
        set(.tags, tagsW)
        set(.group, groupW)
        set(.history, 148)
        set(.latency, latW)
        set(.version, verW)
        table.sizeLastColumnToFit()
        table.headerView?.menu = columnMenu()
    }

    private func matches(_ n: Node) -> Bool {
        if n.kind == "info" { return false }
        if n.children.contains(where: matches) { return true }
        switch store.filterStatus {
        case "up":
            if !(n.ok && !n.warn) || n.kind == "group" { return false }
        case "down":
            if n.ok || n.kind == "group" { return false }
        case "degraded":
            if !n.warn || n.kind == "group" { return false }
        default: break
        }
        if filter.isEmpty { return true }
        return n.title.lowercased().contains(filter)
            || n.kind.lowercased().contains(filter)
            || n.target.lowercased().contains(filter)
            || n.status.lowercased().contains(filter)
            || n.tags.contains(where: { $0.lowercased().contains(filter) })
            || n.group.lowercased().contains(filter)
            || n.version.lowercased().contains(filter)
    }

    private func grouped(_ items: [Node]) -> [Node] {
        switch store.groupBy {
        case .none: return items
        case .kind: return buckets(items) { $0.kind == "group" ? $0.group : ($0.kind == "TCP" ? "TCP" : $0.kind == "HTTP" ? "HTTP" : $0.kind) }
        case .tag: return buckets(items) { $0.group.isEmpty ? "Other" : $0.group }
        }
    }

    private func buckets(_ items: [Node], key: (Node) -> String) -> [Node] {
        var map: [String: [Node]] = [:]
        for n in items { map[key(n), default: []].append(n) }
        let pref = store.groupOrder
        let names = pref.filter { map[$0] != nil } + map.keys.filter { !pref.contains($0) }.sorted()
        return names.compactMap { name in
            guard let kids = map[name], !kids.isEmpty else { return nil }
            let up = kids.filter(\.ok).count
            return Node(
                id: "g-\(name)", title: name, kind: "group",
                status: "\(up)/\(kids.count) up",
                ok: kids.allSatisfy(\.ok),
                warn: kids.contains(where: \.warn),
                spark: Array(kids.flatMap(\.spark).suffix(40)),
                latency: "\(up)/\(kids.count)",
                target: "\(kids.count) checks",
                url: nil, leaf: false, tags: [name], group: name,
                children: kids
            )
        }
    }

    private func applyDensity() {
        let compact = store.compact
        table.rowSizeStyle = TableDensity.rowSize(compact)
        table.indentationPerLevel = TableDensity.indent(compact)
        table.intercellSpacing = TableDensity.spacing(compact)
    }

    private func formatLatency(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        if ms >= 10_000 { return "timeout" }
        if ms >= 1000 { return String(format: "%.1fs", ms / 1000) }
        return String(format: "%.0f ms", ms)
    }

    private func tunnelNode(_ t: TunnelRow) -> Node {
        let target = t.port.map { "\(t.host):\($0)" } ?? t.host
        let lat = formatLatency(t.ms)
        var kids: [Node] = []
        kids.append(detail(t.id, "Listen", target))
        if let p = t.process { kids.append(detail(t.id, "Process", p)) }
        if let pid = t.pid { kids.append(detail(t.id, "PID", pid)) }
        if let e = t.elapsed { kids.append(detail(t.id, "Uptime", e)) }
        if let c = t.command { kids.append(detail(t.id, "Command", c)) }
        let life = TunnelLifecycle.shared.state(for: t.id)
        let starting: Bool = if case .starting = life { true } else { false }
        let lifeText = life == .stopped ? "" : TunnelLifecycle.text(life, port: t.port)
        return Node(
            id: t.id, title: t.title, kind: "TCP",
            status: !t.enabled ? "Off" : starting ? "Starting" : t.busy ? "Checking" : (t.up ? "Up" : "Down"),
            ok: t.enabled && t.up, warn: false, spark: t.spark, latency: t.enabled ? lat : "",
            target: lifeText.isEmpty ? target : "\(target) · \(lifeText)", url: nil, leaf: false,
            tags: t.tags, group: t.group, version: "",
            actions: t.enabled ? t.actions : [],
            enabled: t.enabled,
            icon: t.icon, image: t.image,
            children: kids
        )
    }

    private func deployNode(_ d: DeployRow) -> Node {
        let warn = d.health == "degraded"
        let ok = d.health == "healthy"
        let checking = d.health == "…"
        let lat = formatLatency(d.avgMs)
        var kids: [Node] = []
        let compact = store.compact
        if !compact, let u = d.openUrl, !u.isEmpty {
            kids.append(detail(d.id, "URL", u))
        }
        let services = d.checks.filter { !($0.name == "http" && d.checks.count == 1) }
        for c in services {
            let cw = c.status == "degraded"
            let cok = c.status == "healthy"
            kids.append(Node(
                id: "\(d.id)/\(c.name)", title: c.name, kind: "check",
                status: cok ? "Up" : cw ? "Degraded" : "Down",
                ok: cok, warn: cw, spark: c.spark,
                latency: formatLatency(c.ms),
                target: d.openUrl ?? "", url: d.openUrl, leaf: true
            ))
        }
        if !compact, d.liveVersion != "—" && d.liveVersion != "…" {
            kids.append(detail(d.id, "App", d.liveVersion))
        }
        if !compact, d.k8sVersion != "—" && d.k8sVersion != "timeout" && d.k8sVersion != "…" {
            kids.append(detail(d.id, "Deploy", d.k8sVersion))
        }
        if !compact, d.k8sLiveVersion != "—" && d.k8sLiveVersion != "timeout" && d.k8sLiveVersion != "…" {
            kids.append(detail(d.id, "Pod", d.k8sLiveVersion))
        }
        if let u = d.uptime {
            kids.append(detail(d.id, "Uptime", String(format: "%.0fs", u)))
        }
        return Node(
            id: d.id, title: d.title, kind: "HTTP",
            status: !d.enabled ? "Off" : checking ? "Checking" : ok ? "Up" : warn ? "Degraded" : "Down",
            ok: d.enabled && ok, warn: d.enabled && warn, spark: d.spark, latency: d.enabled ? lat : "",
            target: d.openUrl ?? "", url: d.openUrl, leaf: false,
            tags: d.tags, group: d.group,
            version: (d.liveVersion == "—" || d.liveVersion == "…") ? "" : d.liveVersion,
            actions: d.enabled ? d.actions : [],
            enabled: d.enabled,
            icon: d.icon, image: d.image,
            children: kids
        )
    }

    private func detail(_ parent: String, _ title: String, _ value: String) -> Node {
        Node(
            id: "\(parent)/d-\(title)", title: title, kind: "info",
            status: "", ok: true, warn: false, spark: [], latency: "",
            target: value, url: nil, leaf: true
        )
    }

    @objc private func clicked() {
        if dragging { return }
        let i = table.clickedRow
        guard i >= 0, let n = table.item(atRow: i) as? Node, !n.children.isEmpty else { return }
        if let ev = NSApp.currentEvent {
            let p = table.convert(ev.locationInWindow, from: nil)
            if table.frameOfOutlineCell(atRow: i).insetBy(dx: -4, dy: -4).contains(p) { return }
        }
        if table.isItemExpanded(n) {
            table.collapseItem(n)
            expanded.remove(n.id)
        } else {
            table.expandItem(n)
            expanded.insert(n.id)
        }
    }

    @objc private func openRow() {
        let i = table.clickedRow
        guard i >= 0, let n = table.item(atRow: i) as? Node, let s = n.url, let u = URL(string: s) else { return }
        NSWorkspace.shared.open(u)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Node)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        !((item as? Node)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let n = item as? Node, n.kind != "info", n.kind != "check" else { return nil }
        dragging = true
        let p = NSPasteboardItem()
        p.setString(n.id, forType: .string)
        return p
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        dragging = false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        if index == NSOutlineViewDropOnItemIndex { return [] }
        if let n = item as? Node, n.kind != "group" { return [] }
        return .move
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard let id = info.draggingPasteboard.string(forType: .string) else { return false }
        let parent = item as? Node
        let siblings = parent == nil
            ? roots
            : parent!.children.filter { $0.kind != "info" && $0.kind != "check" }
        var ids = siblings.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return false }
        var to = index
        ids.remove(at: from)
        if from < to { to -= 1 }
        to = min(max(0, to), ids.count)
        ids.insert(id, at: to)
        table.sortDescriptors = []
        if parent == nil, siblings.first?.kind == "group" {
            store.reorderGroups(ids.map { $0.hasPrefix("g-") ? String($0.dropFirst(2)) : $0 })
        } else {
            store.reorderSiblings(ids)
        }
        dragging = false
        return true
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let n = notification.userInfo?["NSObject"] as? Node { expanded.insert(n.id) }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let n = notification.userInfo?["NSObject"] as? Node { expanded.remove(n.id) }
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        if let d = outlineView.sortDescriptors.first {
            store.sortKey = d.key ?? ""
            store.sortAscending = d.ascending
        } else {
            store.sortKey = ""
        }
        store.persistTablePrefs()
        let keep = expandedIds()
        roots = sortNodes(roots)
        table.reloadData()
        restoreExpanded(keep)
    }

    private func restoreExpanded(_ keep: Set<String>) {
        func walk(_ nodes: [Node]) {
            for n in nodes {
                let seed = n.kind == "group" && !seededGroups
                if keep.contains(n.id) || seed || (!filter.isEmpty && !n.children.isEmpty) {
                    table.expandItem(n)
                    walk(n.children)
                }
            }
        }
        walk(roots)
        if !seededGroups { seededGroups = true }
    }

    private func expandedIds() -> Set<String> {
        var s = expanded
        func walk(_ nodes: [Node]) {
            for n in nodes {
                if table.isItemExpanded(n) { s.insert(n.id) }
                walk(n.children)
            }
        }
        walk(roots)
        expanded = s
        return s
    }

    private func sortNodes(_ nodes: [Node]) -> [Node] {
        let descs = table.sortDescriptors
        let checks = nodes.filter { $0.kind != "info" }
        let infos = nodes.filter { $0.kind == "info" }
        let ordered: [Node]
        if descs.isEmpty {
            ordered = checks
        } else {
            ordered = checks.sorted { a, b in
                for d in descs {
                    let c = compare(a, b, key: d.key ?? Col.name.rawValue)
                    if c != .orderedSame {
                        return d.ascending ? c == .orderedAscending : c == .orderedDescending
                    }
                }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
        for n in ordered { n.children = sortNodes(n.children) }
        return ordered + infos
    }

    private func compare(_ a: Node, _ b: Node, key: String) -> ComparisonResult {
        switch Col(rawValue: key) {
        case .name:
            return a.title.localizedStandardCompare(b.title)
        case .kind:
            return a.kind.localizedStandardCompare(b.kind)
        case .tags:
            return a.tags.joined(separator: ",").localizedStandardCompare(b.tags.joined(separator: ","))
        case .target:
            return a.target.localizedStandardCompare(b.target)
        case .status:
            return cmp(statusRank(a), statusRank(b))
        case .latency:
            return cmp(latencyValue(a), latencyValue(b))
        case .history:
            return cmp(a.spark.last ?? -1, b.spark.last ?? -1)
        case .group:
            return a.group.localizedStandardCompare(b.group)
        case .version:
            return a.version.localizedStandardCompare(b.version)
        default:
            return a.title.localizedStandardCompare(b.title)
        }
    }

    private func cmp<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }

    private func statusRank(_ n: Node) -> Int {
        if n.kind == "info" { return 4 }
        if n.status == "Checking" { return 2 }
        if n.warn { return 1 }
        if n.ok { return 3 }
        return 0
    }

    private func latencyValue(_ n: Node) -> Double {
        let s = n.latency.replacingOccurrences(of: ",", with: "")
        if let d = Double(s.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map(String.init) ?? "") {
            return d
        }
        return -1
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let raw = tableColumn?.identifier.rawValue, let col = Col(rawValue: raw), let r = item as? Node else { return nil }
        let info = r.kind == "info"
        switch col {
        case .status:
            let id = NSUserInterfaceItemIdentifier("status-dot")
            let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? StatusCell) ?? StatusCell()
            cell.identifier = id
            cell.apply(
                image: info ? nil : statusImage(r),
                status: r.status,
                checking: r.status == "Checking" || r.status == "Starting",
                compact: store.compact
            )
            return cell
        case .name:
            let id = NSUserInterfaceItemIdentifier("name-act")
            let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NameCell) ?? NameCell()
            cell.identifier = id
            cell.apply(
                title: r.title,
                info: info,
                group: r.kind == "group",
                enabled: r.enabled,
                image: r.image,
                icon: r.icon,
                kind: r.kind,
                checkId: r.id,
                actions: [],
                busy: r.status == "Checking",
                compact: store.compact
            )
            return cell
        case .kind:
            let id = NSUserInterfaceItemIdentifier("kind-chip")
            let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? TagsCell) ?? TagsCell()
            cell.identifier = id
            cell.apply(info || r.kind == "group" ? [] : [r.kind], muted: true)
            return cell
        case .tags:
            let id = NSUserInterfaceItemIdentifier("tags-chip")
            let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? TagsCell) ?? TagsCell()
            cell.identifier = id
            cell.apply(r.kind == "group" || r.kind == "info" ? [] : r.tags, muted: false)
            return cell
        case .group:
            let cell = textCell(outlineView, id: "group")
            cell.textField?.stringValue = r.kind == "group" || r.kind == "info" ? "" : r.group
            cell.textField?.font = .systemFont(ofSize: 12)
            cell.textField?.textColor = .secondaryLabelColor
            return cell
        case .version:
            let cell = textCell(outlineView, id: "ver")
            cell.textField?.stringValue = r.version
            cell.textField?.font = .systemFont(ofSize: 12)
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.lineBreakMode = .byTruncatingMiddle
            cell.toolTip = r.version
            return cell
        case .history:
            let id = NSUserInterfaceItemIdentifier("history")
            let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? HistoryCell) ?? HistoryCell()
            cell.identifier = id
            cell.apply(info ? [] : r.spark, compact: store.compact)
            return cell
        case .latency:
            let cell = textCell(outlineView, id: "lat")
            cell.textField?.stringValue = r.latency
            cell.textField?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.alignment = .right
            return cell
        case .target:
            let cell = textCell(outlineView, id: "tgt")
            cell.textField?.stringValue = r.target
            cell.textField?.font = .systemFont(ofSize: 12)
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.lineBreakMode = .byTruncatingMiddle
            cell.toolTip = r.target
            return cell
        case .actions:
            let id = NSUserInterfaceItemIdentifier("actions")
            let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? ActionCell) ?? ActionCell()
            cell.identifier = id
            let shown = (r.kind == "group" || r.kind == "info")
                ? []
                : r.actions.filter { $0.isVisible(up: r.ok && !r.warn) }
            cell.apply(checkId: r.id, actions: shown, enabled: r.enabled && r.status != "Checking")
            return cell
        }
    }

    private func statusImage(_ r: Node) -> NSImage? {
        let name: String
        let color: NSColor
        if !r.enabled {
            name = "pause.circle.fill"
            color = .tertiaryLabelColor
        } else if r.warn {
            name = "exclamationmark.circle.fill"
            color = .systemOrange
        } else if r.ok {
            name = "checkmark.circle.fill"
            color = .systemGreen
        } else if r.status == "Checking" || r.status == "Starting" {
            name = "ellipsis.circle.fill"
            color = .tertiaryLabelColor
        } else {
            name = "xmark.circle.fill"
            color = .systemRed
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: r.status)
        let cfg = NSImage.SymbolConfiguration(pointSize: TableDensity.symbol(store.compact), weight: .medium)
            .applying(.init(paletteColors: [color]))
        return img?.withSymbolConfiguration(cfg)
    }

    private func textCell(_ tableView: NSOutlineView, id: String) -> NSTableCellView {
        let ident = NSUserInterfaceItemIdentifier(id)
        if let v = tableView.makeView(withIdentifier: ident, owner: self) as? NSTableCellView { return v }
        let v = NSTableCellView()
        v.identifier = ident
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.lineBreakMode = .byTruncatingTail
        tf.drawsBackground = false
        tf.isBezeled = false
        tf.isEditable = false
        v.addSubview(tf)
        v.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
            tf.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        guard row >= 0, let n = table.item(atRow: row) as? Node else { return }
        if n.kind != "info", n.kind != "check", n.kind != "group" {
            let tog = NSMenuItem(
                title: n.enabled ? "Disable" : "Enable",
                action: #selector(toggleEnabled(_:)),
                keyEquivalent: ""
            )
            tog.target = self
            tog.representedObject = n.id
            menu.addItem(tog)
            if !n.actions.isEmpty { menu.addItem(.separator()) }
        }
        let shown = n.actions.filter { $0.isVisible(up: n.ok && !n.warn) }
        let enabled = n.enabled && n.status != "Checking"
        for a in shown {
            let it = NSMenuItem(title: a.title, action: #selector(runRowAction(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = [n.id, a.id]
            it.isEnabled = enabled
            menu.addItem(it)
        }
    }

    @objc func runRowAction(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        Store.shared.runAction(checkId: pair[0], actionId: pair[1])
    }

    @objc func toggleEnabled(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let on = store.allChecks().first(where: { $0.id == id })?.isEnabled ?? true
        store.setCheckEnabled(id, !on)
    }
}

private final class StatusCell: NSTableCellView {
    private var lastStatus: String?
    private var iconSize: NSLayoutConstraint?
    private var iconHeight: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.wantsLayer = true
        iv.imageScaling = .scaleProportionallyDown
        addSubview(iv)
        imageView = iv
        let w = iv.widthAnchor.constraint(equalToConstant: 22)
        let h = iv.heightAnchor.constraint(equalToConstant: 22)
        iconSize = w
        iconHeight = h
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor),
            w, h,
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(image: NSImage?, status: String, checking: Bool, compact: Bool) {
        let size = TableDensity.icon(compact)
        iconSize?.constant = size
        iconHeight?.constant = size
        imageView?.isHidden = image == nil
        let changed = lastStatus != nil && lastStatus != status
        lastStatus = status
        imageView?.image = image
        toolTip = status
        imageView?.layer?.removeAnimation(forKey: "status-pulse")
        imageView?.layer?.removeAnimation(forKey: "status-check")
        guard let layer = imageView?.layer, !Motion.reduce else { return }
        if checking {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.35
            pulse.toValue = 1
            pulse.duration = 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: "status-check")
        } else if changed {
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.25, 1.06, 1]
            scale.keyTimes = [0, 0.72, 1]
            scale.duration = 0.32
            scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.28
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            layer.add(scale, forKey: "status-pulse")
            layer.add(fade, forKey: "status-fade")
        }
    }
}

private final class NameCell: NSTableCellView {
    private var checkId = ""
    private var actions: [CheckAction] = []
    private let stack = NSStackView()
    private var stackWidth: NSLayoutConstraint?
    private var iconW: NSLayoutConstraint?
    private var iconH: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyDown
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.lineBreakMode = .byTruncatingTail
        tf.drawsBackground = false
        tf.isBezeled = false
        tf.isEditable = false
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iv)
        addSubview(tf)
        addSubview(stack)
        imageView = iv
        textField = tf
        let sw = stack.widthAnchor.constraint(equalToConstant: 0)
        stackWidth = sw
        let iw = iv.widthAnchor.constraint(equalToConstant: 16)
        let ih = iv.heightAnchor.constraint(equalToConstant: 16)
        iconW = iw
        iconH = ih
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor),
            iw, ih,
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 8),
            tf.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: tf.trailingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            sw,
        ])
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    func apply(
        title: String, info: Bool, group: Bool, enabled: Bool,
        image: String?, icon: String?, kind: String,
        checkId: String, actions: [CheckAction], busy: Bool, compact: Bool
    ) {
        self.checkId = checkId
        self.actions = actions
        let side = TableDensity.icon(compact)
        iconW?.constant = side
        iconH?.constant = side
        textField?.stringValue = title
        textField?.font = TableDensity.nameFont(compact, group: group, info: info)
        textField?.textColor = info || !enabled ? .secondaryLabelColor : .labelColor
        imageView?.isHidden = info
        if let img = CheckArt.nsImage(image) {
            img.size = NSSize(width: side, height: side)
            imageView?.image = img
            imageView?.contentTintColor = nil
        } else {
            let k: CheckKind = kind == "TCP" ? .tcp : kind == "HTTP" ? .http : .command
            let fallback = group ? "folder" : kind == "check" ? "circle" : kind == "info" ? "info.circle" : CheckArt.symbol(icon: icon, kind: k, enabled: true)
            imageView?.image = NSImage(systemSymbolName: fallback, accessibilityDescription: kind)
            imageView?.contentTintColor = .secondaryLabelColor
        }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (i, a) in actions.enumerated() {
            let b = NSButton(title: a.title, target: self, action: #selector(tap(_:)))
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            b.tag = i
            b.isEnabled = enabled && !busy
            b.toolTip = a.title
            stack.addArrangedSubview(b)
        }
        stackWidth?.isActive = false
        stackWidth = stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        stackWidth?.isActive = true
        toolTip = title
    }

    @objc private func tap(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        Store.shared.runAction(checkId: checkId, actionId: actions[sender.tag].id)
    }
}

private final class HistoryCell: NSTableCellView {
    let beat = HeartbeatView()
    private var height: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        beat.translatesAutoresizingMaskIntoConstraints = false
        addSubview(beat)
        let h = beat.heightAnchor.constraint(equalToConstant: 18)
        height = h
        NSLayoutConstraint.activate([
            beat.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            beat.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            beat.centerYAnchor.constraint(equalTo: centerYAnchor),
            h,
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ spark: [Double], compact: Bool) {
        beat.values = spark
        beat.slots = TableDensity.historySlots(compact)
        height?.constant = TableDensity.historyHeight(compact)
        toolTip = spark.isEmpty ? "No history yet" : "Last \(spark.count) checks"
    }
}

private final class TagChip: NSView {
    private let label = NSTextField(labelWithString: "")
    var muted = false
    var text = "" {
        didSet { label.stringValue = text; needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.drawsBackground = false
        label.isBezeled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let s = label.intrinsicContentSize
        return NSSize(width: s.width + 14, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        let (bg, fg) = muted
            ? (NSColor.quaternaryLabelColor.withAlphaComponent(0.18), NSColor.secondaryLabelColor)
            : TagTint.colors(text)
        label.textColor = fg
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        bg.setFill()
        path.fill()
    }
}

private final class TagsCell: NSTableCellView {
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ tags: [String], muted: Bool) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for t in tags {
            let chip = TagChip()
            chip.muted = muted
            chip.text = t
            stack.addArrangedSubview(chip)
        }
        toolTip = tags.joined(separator: ", ")
    }
}

private final class ActionCell: NSTableCellView {
    private var checkId = ""
    private var actions: [CheckAction] = []
    private let button = NSPopUpButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button.pullsDown = true
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = #selector(picked(_:))
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 36),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(checkId: String, actions: [CheckAction], enabled: Bool) {
        self.checkId = checkId
        self.actions = actions
        button.removeAllItems()
        button.isHidden = actions.isEmpty
        button.isEnabled = enabled && !actions.isEmpty
        guard !actions.isEmpty else { return }
        button.addItem(withTitle: "")
        let head = button.item(at: 0)
        head?.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Actions")
        head?.title = ""
        for a in actions {
            button.addItem(withTitle: a.title)
            let item = button.lastItem
            item?.representedObject = a.id
            if let icon = a.icon {
                item?.image = NSImage(systemSymbolName: icon, accessibilityDescription: a.title)
            }
        }
        button.toolTip = actions.map(\.title).joined(separator: ", ")
        button.selectItem(at: 0)
    }

    @objc private func picked(_ sender: NSPopUpButton) {
        defer { sender.selectItem(at: 0) }
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        Store.shared.runAction(checkId: checkId, actionId: id)
    }
}
