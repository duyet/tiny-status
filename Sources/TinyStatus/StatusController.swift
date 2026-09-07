import AppKit
import Combine

final class OutlineItem: NSObject {
    enum Kind { case overview, header, tunnel, deploy }
    let kind: Kind
    let id: String
    let title: String
    var children: [OutlineItem] = []
    init(kind: Kind, id: String, title: String, children: [OutlineItem] = []) {
        self.kind = kind
        self.id = id
        self.title = title
        self.children = children
    }
}

final class SidebarCell: NSTableCellView {
    let iconView = NSImageView()
    let label = NSTextField(labelWithString: "")
    let dot = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 13, weight: .regular)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(label)
        addSubview(dot)
        imageView = iconView
        textField = label
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: dot.leadingAnchor, constant: -6),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(title: String, image: NSImage?, header: Bool, ok: Bool?) {
        label.stringValue = title
        iconView.image = image
        iconView.isHidden = header
        if header {
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .tertiaryLabelColor
            dot.isHidden = true
        } else {
            label.font = .systemFont(ofSize: 13, weight: .regular)
            label.textColor = .labelColor
            if let ok {
                dot.isHidden = false
                dot.layer?.backgroundColor = (ok ? NSColor.systemGreen : NSColor.systemOrange).cgColor
            } else {
                dot.isHidden = true
            }
        }
    }
}

final class StatusController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    private let store = Store.shared
    private var bag = Set<AnyCancellable>()
    private var roots: [OutlineItem] = []
    private var filter = ""
    private let outline = NSOutlineView()
    private let search = NSSearchField()
    private let titleLabel = NSTextField(labelWithString: "Overview")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let chartBox = NSBox()
    private let chartTitle = NSTextField(labelWithString: "Health")
    private let bars = BarChartView()
    private let body = NSTextField(wrappingLabelWithString: "")
    private var chartHeight: NSLayoutConstraint?

    override func loadView() {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        search.placeholderString = "Search"
        search.delegate = self
        search.focusRingType = .none
        search.translatesAutoresizingMaskIntoConstraints = false
        let sideScroll = NSScrollView()
        sideScroll.drawsBackground = false
        sideScroll.borderType = .noBorder
        sideScroll.hasVerticalScroller = true
        sideScroll.autohidesScrollers = true
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.delegate = self
        outline.dataSource = self
        outline.backgroundColor = .clear
        outline.style = .sourceList
        outline.rowHeight = 28
        outline.indentationPerLevel = 10
        outline.intercellSpacing = NSSize(width: 0, height: 1)
        sideScroll.documentView = outline
        sideScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(search)
        sidebar.addSubview(sideScroll)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor, constant: 8),
            search.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            search.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            sideScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            sideScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sideScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sideScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
        ])

        let detail = NSView()
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        chartTitle.font = .systemFont(ofSize: 13, weight: .medium)
        chartTitle.textColor = .secondaryLabelColor
        chartBox.boxType = .custom
        chartBox.cornerRadius = 10
        chartBox.borderWidth = 0
        chartBox.fillColor = NSColor.controlBackgroundColor
        chartBox.contentViewMargins = NSSize(width: 16, height: 12)
        chartBox.translatesAutoresizingMaskIntoConstraints = false
        let chartStack = NSStackView(views: [chartTitle, bars])
        chartStack.orientation = .vertical
        chartStack.alignment = .leading
        chartStack.spacing = 8
        chartStack.translatesAutoresizingMaskIntoConstraints = false
        chartBox.contentView = chartStack
        bars.translatesAutoresizingMaskIntoConstraints = false
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        for v in [titleLabel, subtitle, chartBox, body] {
            v.translatesAutoresizingMaskIntoConstraints = false
            detail.addSubview(v)
        }
        let ch = chartBox.heightAnchor.constraint(equalToConstant: 180)
        chartHeight = ch
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: detail.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -28),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            chartBox.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            chartBox.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            chartBox.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            ch,
            bars.heightAnchor.constraint(equalToConstant: 132),
            body.topAnchor.constraint(equalTo: chartBox.bottomAnchor, constant: 14),
            body.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        split.addSubview(sidebar)
        split.addSubview(detail)
        view = split
        DispatchQueue.main.async { split.setPosition(220, ofDividerAt: 0) }
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
        let selected = (outline.item(atRow: outline.selectedRow) as? OutlineItem)?.id
        var items: [OutlineItem] = [OutlineItem(kind: .overview, id: "overview", title: "Overview")]
        if !store.tunnels.isEmpty {
            let t = OutlineItem(kind: .header, id: "h-tun", title: "Tunnels")
            t.children = store.tunnels
                .filter { filter.isEmpty || $0.title.lowercased().contains(filter) }
                .map { OutlineItem(kind: .tunnel, id: $0.id, title: $0.title) }
            items.append(t)
        }
        for g in regionGroups(store.deploys) {
            let kids = g.items.filter { filter.isEmpty || $0.title.lowercased().contains(filter) }
            guard !kids.isEmpty else { continue }
            let n = OutlineItem(kind: .header, id: "h-\(g.key)", title: g.key)
            n.children = kids.map { OutlineItem(kind: .deploy, id: $0.id, title: envLabel($0.title)) }
            items.append(n)
        }
        roots = items
        outline.reloadData()
        for r in roots { outline.expandItem(r) }
        if let selected {
            func select(_ item: OutlineItem) -> Bool {
                if item.id == selected {
                    outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: item)), byExtendingSelection: false)
                    return true
                }
                return item.children.contains(where: select)
            }
            for r in roots where select(r) { break }
        } else {
            outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        showSelection()
        AppDelegate.instance?.setStatus(ok: store.allOK)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? OutlineItem)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? OutlineItem)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? OutlineItem)?.kind == .header
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? OutlineItem)?.kind != .header
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { false }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        (item as? OutlineItem)?.kind == .header ? 22 : 28
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? OutlineItem else { return nil }
        let id = NSUserInterfaceItemIdentifier("side")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? SidebarCell) ?? SidebarCell()
        cell.identifier = id
        cell.apply(title: n.title, image: icon(for: n), header: n.kind == .header, ok: statusOK(n))
        cell.toolTip = tooltip(for: n)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        showSelection()
    }

    private func showSelection() {
        let n = outline.item(atRow: outline.selectedRow) as? OutlineItem
        if n == nil || n?.kind == .overview || n?.kind == .header {
            titleLabel.stringValue = "Overview"
            subtitle.stringValue = "\(store.tunnelsUp)/\(store.tunnels.count) tunnels up · \(store.healthyDeploys)/\(store.deploys.count) apps healthy"
            chartTitle.stringValue = "Healthy apps"
            bars.values = regionGroups(store.deploys).map { g in
                let ok = g.items.filter { $0.health == "healthy" }.count
                return (g.key, Double(ok), ok == g.items.count)
            }
            setChartVisible(!bars.values.isEmpty)
            var lines: [String] = []
            if store.degradedDeploys > 0 { lines.append("\(store.degradedDeploys) degraded") }
            if store.downDeploys > 0 { lines.append("\(store.downDeploys) down") }
            if store.driftDeploys > 0 { lines.append("\(store.driftDeploys) version drift") }
            body.stringValue = lines.joined(separator: "  ·  ")
            return
        }
        switch n!.kind {
        case .overview, .header: break
        case .tunnel:
            guard let t = store.tunnels.first(where: { $0.id == n!.id }) else { return }
            titleLabel.stringValue = t.title
            subtitle.stringValue = t.up
                ? "Listening on \(t.host):\(t.port ?? 0)"
                : "Nothing listening on \(t.host):\(t.port ?? 0)"
            chartTitle.stringValue = "Listen"
            bars.values = [("port", t.up ? 1 : 0, t.up)]
            setChartVisible(true)
            var extra: [String] = []
            if let p = t.process { extra.append(p) }
            if let pid = t.pid { extra.append("pid \(pid)") }
            if let e = t.elapsed { extra.append("up \(e)") }
            body.stringValue = extra.joined(separator: "  ·  ")
        case .deploy:
            guard let d = store.deploys.first(where: { $0.id == n!.id }) else { return }
            titleLabel.stringValue = d.title
            let avg = d.avgMs.map { String(format: "%.0f ms", $0) } ?? "—"
            subtitle.stringValue = "\(d.health.capitalized) · \(d.okCount)/\(d.checks.count) checks · \(avg)"
            chartTitle.stringValue = "Latency"
            bars.values = d.checks.map { ($0.name, $0.ms ?? 0, $0.status == "healthy") }
            if bars.values.isEmpty {
                bars.values = [("health", DeployRow.healthScore(d.health), d.up)]
            }
            setChartVisible(true)
            var extra = "app \(d.liveVersion)  ·  deploy \(d.k8sVersion)"
            if let u = d.uptime { extra += String(format: "  ·  %.0fs", u) }
            body.stringValue = extra
        }
    }

    private func setChartVisible(_ on: Bool) {
        chartBox.isHidden = !on
        chartHeight?.constant = on ? 180 : 0
    }

    private func statusOK(_ n: OutlineItem) -> Bool? {
        switch n.kind {
        case .overview, .header: return nil
        case .tunnel: return store.tunnels.first(where: { $0.id == n.id })?.up
        case .deploy: return store.deploys.first(where: { $0.id == n.id })?.health == "healthy"
        }
    }

    private func icon(for n: OutlineItem) -> NSImage? {
        let name: String
        switch n.kind {
        case .header: return nil
        case .overview: name = "square.grid.2x2"
        case .tunnel: name = "network"
        case .deploy: name = "circle"
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: n.title)
        img?.isTemplate = true
        return img
    }

    private func tooltip(for n: OutlineItem) -> String {
        switch n.kind {
        case .overview: return "All checks"
        case .header: return n.title
        case .tunnel: return "TCP"
        case .deploy: return "HTTP"
        }
    }
}
