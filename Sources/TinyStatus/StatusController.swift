import AppKit
import Combine

private enum Col: String, CaseIterable {
    case status, name, kind, tags, history, latency, target
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
    var children: [Node] = []

    init(
        id: String, title: String, kind: String, status: String, ok: Bool, warn: Bool,
        spark: [Double], latency: String, target: String, url: String?, leaf: Bool,
        tags: [String] = [], group: String = "",
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
        self.children = children
    }
}

final class StatusController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    let search = NSSearchField()
    private let store = Store.shared
    private var bag = Set<AnyCancellable>()
    private var roots: [Node] = []
    private var filter = ""
    private let table = NSOutlineView()
    private let empty = NSTextField(wrappingLabelWithString: "No checks yet. Choose TinyStatus → Import checks…")

    override func loadView() {
        search.placeholderString = "Filter"
        search.delegate = self
        search.sendsWholeSearchString = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]

        table.delegate = self
        table.dataSource = self
        table.rowSizeStyle = .medium
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 6, height: 0)
        table.indentationPerLevel = 14
        table.indentationMarkerFollowsCell = true
        table.action = #selector(clicked)
        table.doubleAction = #selector(openRow)
        table.target = self
        table.autosaveName = "TinyStatus.checks.v2"
        table.autosaveTableColumns = false

        addCol(.status, "", 32, min: 28, max: 36, flex: false)
        addCol(.name, "Check", 160, min: 96, max: 420, flex: false)
        addCol(.kind, "Type", 52, min: 44, max: 72, flex: false)
        addCol(.tags, "Tags", 80, min: 56, max: 220, flex: false)
        addCol(.history, "History", 148, min: 120, max: 200, flex: false)
        addCol(.latency, "Latency", 64, min: 52, max: 88, flex: false)
        addCol(.target, "Target", 240, min: 80, max: 4000, flex: true)
        table.outlineTableColumn = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(Col.name.rawValue))
        if table.sortDescriptors.isEmpty {
            table.sortDescriptors = [NSSortDescriptor(key: Col.name.rawValue, ascending: true)]
        }
        scroll.documentView = table

        empty.font = .systemFont(ofSize: 13)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.isHidden = true
        empty.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 480))
        scroll.frame = root.bounds
        root.addSubview(scroll)
        root.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
        ])
        view = root
    }

    private func addCol(_ id: Col, _ title: String, _ w: CGFloat, min: CGFloat, max: CGFloat, flex: Bool) {
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.rawValue))
        c.title = title
        c.width = w
        c.minWidth = min
        c.maxWidth = max
        c.resizingMask = flex ? [.userResizingMask, .autoresizingMask] : [.userResizingMask]
        c.sortDescriptorPrototype = NSSortDescriptor(key: id.rawValue, ascending: true)
        table.addTableColumn(c)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.reload()
        }.store(in: &bag)
        reload()
    }

    func controlTextDidChange(_ obj: Notification) {
        filter = search.stringValue.lowercased()
        reload()
    }

    func reload() {
        let keep = expandedIds()
        var items: [Node] = []
        for t in store.tunnels {
            let n = tunnelNode(t)
            if matches(n) { items.append(n) }
        }
        for d in store.deploys {
            let n = deployNode(d)
            if matches(n) { items.append(n) }
        }
        roots = sortNodes(grouped(items))
        empty.isHidden = !items.isEmpty
        table.reloadData()
        restoreExpanded(keep)
        sizeColumnsToContent()
        view.window?.subtitle = items.isEmpty ? "" : "\(store.healthCheckSummary) · \(store.lastCheckedLabel)"
        AppDelegate.instance?.setStatus(ok: store.allOK)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        table.sizeLastColumnToFit()
    }

    private func sizeColumnsToContent() {
        let body = NSFont.systemFont(ofSize: 13)
        let small = NSFont.systemFont(ofSize: 12)
        let tagsFont = NSFont.systemFont(ofSize: 11)
        let header = NSFont.systemFont(ofSize: 11, weight: .medium)
        func textW(_ s: String, _ font: NSFont) -> CGFloat {
            ceil((s as NSString).size(withAttributes: [.font: font]).width)
        }
        var nameW: CGFloat = textW("Check", header) + 24
        var kindW: CGFloat = textW("Type", header) + 20
        var tagsW: CGFloat = textW("Tags", header) + 20
        var latW: CGFloat = textW("Latency", header) + 20
        var hasTags = false
        func walk(_ nodes: [Node], level: Int) {
            for n in nodes {
                nameW = max(nameW, 28 + CGFloat(level) * table.indentationPerLevel + 18 + textW(n.title, n.kind == "group" ? .systemFont(ofSize: 13, weight: .semibold) : body) + 12)
                if n.kind != "info" && n.kind != "group" {
                    kindW = max(kindW, textW(n.kind, small) + 20)
                }
                if !n.tags.isEmpty, n.kind != "group" {
                    hasTags = true
                    tagsW = max(tagsW, textW(n.tags.joined(separator: "  "), tagsFont) + 20)
                }
                if !n.latency.isEmpty {
                    latW = max(latW, textW(n.latency, .monospacedDigitSystemFont(ofSize: 12, weight: .regular)) + 20)
                }
                walk(n.children, level: level + 1)
            }
        }
        walk(roots, level: 0)
        func set(_ id: Col, _ w: CGFloat) {
            guard let c = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id.rawValue)) else { return }
            c.width = min(c.maxWidth, max(c.minWidth, w))
        }
        set(.status, 32)
        set(.name, nameW)
        set(.kind, kindW)
        if let tagsCol = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(Col.tags.rawValue)) {
            tagsCol.isHidden = !hasTags
            if hasTags { tagsCol.width = min(tagsCol.maxWidth, max(tagsCol.minWidth, tagsW)) }
        }
        set(.history, 148)
        set(.latency, latW)
        table.sizeLastColumnToFit()
    }

    private func expandedIds() -> Set<String> {
        var s = store.expanded
        for n in roots where table.isItemExpanded(n) { s.insert(n.id) }
        store.expanded = s
        return s
    }

    private func matches(_ n: Node) -> Bool {
        if filter.isEmpty { return true }
        if n.title.lowercased().contains(filter)
            || n.kind.lowercased().contains(filter)
            || n.target.lowercased().contains(filter)
            || n.status.lowercased().contains(filter)
            || n.tags.contains(where: { $0.lowercased().contains(filter) })
            || n.group.lowercased().contains(filter)
        {
            return true
        }
        return n.children.contains(where: matches)
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

    private func tunnelNode(_ t: TunnelRow) -> Node {
        let target = t.port.map { "\(t.host):\($0)" } ?? t.host
        let lat = t.ms.map { String(format: "%.0f ms", $0) } ?? "—"
        var kids: [Node] = []
        kids.append(detail(t.id, "Listen", target))
        if let p = t.process { kids.append(detail(t.id, "Process", p)) }
        if let pid = t.pid { kids.append(detail(t.id, "PID", pid)) }
        if let e = t.elapsed { kids.append(detail(t.id, "Uptime", e)) }
        if let c = t.command { kids.append(detail(t.id, "Command", c)) }
        return Node(
            id: t.id, title: t.title, kind: "TCP",
            status: t.busy ? "Checking" : (t.up ? "Up" : "Down"),
            ok: t.up, warn: false, spark: t.spark, latency: lat, target: target, url: nil, leaf: false,
            tags: t.tags, group: t.group,
            children: kids
        )
    }

    private func deployNode(_ d: DeployRow) -> Node {
        let warn = d.health == "degraded"
        let ok = d.health == "healthy"
        let checking = d.health == "…"
        let lat = d.avgMs.map { String(format: "%.0f ms", $0) } ?? "—"
        var kids: [Node] = []
        for c in d.checks {
            let cw = c.status == "degraded"
            let cok = c.status == "healthy"
            kids.append(Node(
                id: "\(d.id)/\(c.name)", title: c.name, kind: "check",
                status: cok ? "Up" : cw ? "Degraded" : "Down",
                ok: cok, warn: cw, spark: c.spark,
                latency: c.ms.map { String(format: "%.0f ms", $0) } ?? "—",
                target: d.openUrl ?? "", url: d.openUrl, leaf: true
            ))
        }
        if d.liveVersion != "—" && d.liveVersion != "…" {
            kids.append(detail(d.id, "App", d.liveVersion))
        }
        if d.k8sVersion != "—" && d.k8sVersion != "…" {
            kids.append(detail(d.id, "Deploy", d.k8sVersion))
        }
        if d.k8sLiveVersion != "—" && d.k8sLiveVersion != "…" {
            kids.append(detail(d.id, "Pod", d.k8sLiveVersion))
        }
        if let u = d.uptime {
            kids.append(detail(d.id, "Uptime", String(format: "%.0fs", u)))
        }
        return Node(
            id: d.id, title: d.title, kind: "HTTP",
            status: checking ? "Checking" : ok ? "Up" : warn ? "Degraded" : "Down",
            ok: ok, warn: warn, spark: d.spark, latency: lat,
            target: d.openUrl ?? "", url: d.openUrl, leaf: kids.isEmpty,
            tags: d.tags, group: d.group,
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
        let i = table.clickedRow
        guard i >= 0, let n = table.item(atRow: i) as? Node, !n.children.isEmpty else { return }
        if let ev = NSApp.currentEvent {
            let p = table.convert(ev.locationInWindow, from: nil)
            if table.frameOfOutlineCell(atRow: i).insetBy(dx: -4, dy: -4).contains(p) { return }
        }
        if table.isItemExpanded(n) {
            table.collapseItem(n)
            store.expanded.remove(n.id)
        } else {
            table.expandItem(n)
            store.expanded.insert(n.id)
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

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        let keep = expandedIds()
        roots = sortNodes(roots)
        table.reloadData()
        restoreExpanded(keep)
    }

    private func restoreExpanded(_ keep: Set<String>) {
        let groupKept = keep.filter { $0.hasPrefix("g-") }
        for n in roots {
            if n.kind == "group", groupKept.isEmpty || groupKept.contains(n.id) || !filter.isEmpty {
                table.expandItem(n)
            }
            if keep.contains(n.id) || !filter.isEmpty {
                table.expandItem(n, expandChildren: !filter.isEmpty)
            }
            for c in n.children where keep.contains(c.id) { table.expandItem(c) }
        }
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
            let cell = iconCell(outlineView, id: "status")
            cell.textField?.isHidden = true
            cell.imageView?.isHidden = info
            cell.imageView?.image = info ? nil : statusImage(r)
            cell.toolTip = r.status
            return cell
        case .name:
            let cell = iconCell(outlineView, id: "name")
            cell.textField?.isHidden = false
            cell.textField?.stringValue = r.title
            cell.textField?.font = info ? .systemFont(ofSize: 12) : r.kind == "group" ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
            cell.textField?.textColor = info ? .secondaryLabelColor : .labelColor
            let icon = r.kind == "TCP" ? "network" : r.kind == "HTTP" ? "globe" : r.kind == "check" ? "circle" : r.kind == "group" ? "folder" : "info.circle"
            cell.imageView?.isHidden = info
            cell.imageView?.image = NSImage(systemSymbolName: icon, accessibilityDescription: r.kind)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = r.title
            return cell
        case .kind:
            let cell = textCell(outlineView, id: "kind")
            cell.textField?.stringValue = info || r.kind == "group" ? "" : r.kind
            cell.textField?.font = .systemFont(ofSize: 12)
            cell.textField?.textColor = .secondaryLabelColor
            return cell
        case .tags:
            let cell = textCell(outlineView, id: "tags")
            cell.textField?.stringValue = r.kind == "group" ? "" : r.tags.joined(separator: "  ")
            cell.textField?.font = .systemFont(ofSize: 11)
            cell.textField?.textColor = .tertiaryLabelColor
            cell.toolTip = r.tags.joined(separator: ", ")
            return cell
        case .history:
            let id = NSUserInterfaceItemIdentifier("history")
            let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? HistoryCell) ?? HistoryCell()
            cell.identifier = id
            cell.apply(info ? [] : r.spark)
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
        }
    }

    private func statusImage(_ r: Node) -> NSImage? {
        let name: String
        let color: NSColor
        if r.warn {
            name = "exclamationmark.circle.fill"
            color = .systemOrange
        } else if r.ok {
            name = "checkmark.circle.fill"
            color = .systemGreen
        } else if r.status == "Checking" {
            name = "ellipsis.circle.fill"
            color = .tertiaryLabelColor
        } else {
            name = "xmark.circle.fill"
            color = .systemRed
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: r.status)
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(.init(paletteColors: [color]))
        return img?.withSymbolConfiguration(cfg)
    }

    private func iconCell(_ tableView: NSOutlineView, id: String) -> NSTableCellView {
        let ident = NSUserInterfaceItemIdentifier(id)
        if let v = tableView.makeView(withIdentifier: ident, owner: self) as? NSTableCellView { return v }
        let v = NSTableCellView()
        v.identifier = ident
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.imageScaling = .scaleProportionallyDown
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.lineBreakMode = .byTruncatingTail
        tf.drawsBackground = false
        tf.isBezeled = false
        tf.isEditable = false
        v.addSubview(iv)
        v.addSubview(tf)
        v.imageView = iv
        v.textField = tf
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 2),
            iv.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
            tf.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
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
}

private final class HistoryCell: NSTableCellView {
    let beat = HeartbeatView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        beat.translatesAutoresizingMaskIntoConstraints = false
        addSubview(beat)
        NSLayoutConstraint.activate([
            beat.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            beat.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            beat.centerYAnchor.constraint(equalTo: centerYAnchor),
            beat.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ spark: [Double]) {
        beat.values = spark
        toolTip = spark.isEmpty ? "No history yet" : "Last \(spark.count) checks"
    }
}
