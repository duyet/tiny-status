import AppKit
import Combine

private enum Col: String, CaseIterable {
    case status, name, kind, history, latency, target
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
    var children: [Node] = []

    init(
        id: String, title: String, kind: String, status: String, ok: Bool, warn: Bool,
        spark: [Double], latency: String, target: String, url: String?, leaf: Bool,
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
        table.autosaveName = "TinyStatus.checks"
        table.autosaveTableColumns = true

        addCol(.status, "", 28, min: 24, max: 36)
        addCol(.name, "Check", 220, min: 140, max: 480)
        addCol(.kind, "Type", 56, min: 48, max: 80)
        addCol(.history, "History", 176, min: 120, max: 280)
        addCol(.latency, "Latency", 72, min: 60, max: 100)
        addCol(.target, "Target", 260, min: 120, max: 2000)
        table.outlineTableColumn = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(Col.name.rawValue))
        table.tableColumns.first?.resizingMask = [.userResizingMask]
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

    private func addCol(_ id: Col, _ title: String, _ w: CGFloat, min: CGFloat, max: CGFloat) {
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.rawValue))
        c.title = title
        c.width = w
        c.minWidth = min
        c.maxWidth = max
        c.resizingMask = [.userResizingMask, .autoresizingMask]
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
        var all: [Node] = []
        for t in store.tunnels {
            let n = tunnelNode(t)
            if matches(n) { all.append(n) }
        }
        for d in store.deploys {
            let n = deployNode(d)
            if matches(n) { all.append(n) }
        }
        roots = all
        empty.isHidden = !all.isEmpty
        table.reloadData()
        for n in roots {
            if keep.contains(n.id) || !filter.isEmpty { table.expandItem(n, expandChildren: !filter.isEmpty) }
        }
        view.window?.subtitle = all.isEmpty ? "" : "\(store.healthCheckSummary) · \(store.lastCheckedLabel)"
        AppDelegate.instance?.setStatus(ok: store.allOK)
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
        {
            return true
        }
        return n.children.contains(where: matches)
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
            cell.textField?.font = info ? .systemFont(ofSize: 12) : .systemFont(ofSize: 13)
            cell.textField?.textColor = info ? .secondaryLabelColor : .labelColor
            let icon = r.kind == "TCP" ? "network" : r.kind == "HTTP" ? "globe" : r.kind == "check" ? "circle" : "info.circle"
            cell.imageView?.isHidden = info
            cell.imageView?.image = NSImage(systemSymbolName: icon, accessibilityDescription: r.kind)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = r.title
            return cell
        case .kind:
            let cell = textCell(outlineView, id: "kind")
            cell.textField?.stringValue = info ? "" : r.kind
            cell.textField?.font = .systemFont(ofSize: 12)
            cell.textField?.textColor = .secondaryLabelColor
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
