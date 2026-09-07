import AppKit
import Combine

final class OutlineItem: NSObject {
    enum Kind { case header, tunnel, deploy }
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
    let pill = NSView()
    let iconView = NSImageView()
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8
        pill.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 13, weight: .regular)
        addSubview(pill)
        addSubview(iconView)
        addSubview(label)
        imageView = iconView
        textField = label
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            iconView.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(title: String, image: NSImage?, selected: Bool, header: Bool) {
        label.stringValue = title
        iconView.image = image
        iconView.isHidden = header
        if header {
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            pill.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            label.font = .systemFont(ofSize: 13, weight: .regular)
            label.textColor = .labelColor
            pill.layer?.backgroundColor = selected
                ? NSColor.tertiaryLabelColor.withAlphaComponent(0.18).cgColor
                : NSColor.clear.cgColor
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
    private let chartTitle = NSTextField(labelWithString: "Health history")
    private let bars = BarChartView()
    private let spark = SparkView()
    private let body = NSTextField(wrappingLabelWithString: "")

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
        outline.selectionHighlightStyle = .none
        outline.rowHeight = 32
        outline.indentationPerLevel = 8
        outline.intercellSpacing = NSSize(width: 0, height: 2)
        sideScroll.documentView = outline
        sideScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(search)
        sidebar.addSubview(sideScroll)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: sidebar.safeAreaLayoutGuide.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            sideScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            sideScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sideScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sideScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
        ])

        let detail = NSView()
        detail.wantsLayer = true
        titleLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 3
        chartTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        chartBox.boxType = .custom
        chartBox.cornerRadius = 12
        chartBox.borderWidth = 1
        chartBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.45)
        chartBox.fillColor = .clear
        chartBox.contentViewMargins = NSSize(width: 16, height: 14)
        chartBox.translatesAutoresizingMaskIntoConstraints = false
        let chartStack = NSStackView(views: [chartTitle, bars, spark])
        chartStack.orientation = .vertical
        chartStack.alignment = .leading
        chartStack.spacing = 10
        chartStack.translatesAutoresizingMaskIntoConstraints = false
        chartBox.contentView = chartStack
        bars.translatesAutoresizingMaskIntoConstraints = false
        spark.translatesAutoresizingMaskIntoConstraints = false
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        for v in [titleLabel, subtitle, chartBox, body] {
            v.translatesAutoresizingMaskIntoConstraints = false
            detail.addSubview(v)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: detail.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -32),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            chartBox.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20),
            chartBox.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            chartBox.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            chartBox.heightAnchor.constraint(equalToConstant: 220),
            bars.heightAnchor.constraint(equalToConstant: 140),
            spark.heightAnchor.constraint(equalToConstant: 36),
            body.topAnchor.constraint(equalTo: chartBox.bottomAnchor, constant: 16),
            body.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        split.addSubview(sidebar)
        split.addSubview(detail)
        view = split
        DispatchQueue.main.async { split.setPosition(248, ofDividerAt: 0) }
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
        var items: [OutlineItem] = []
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
            for r in roots {
                if let match = r.children.first(where: { $0.id == selected }) {
                    outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: match)), byExtendingSelection: false)
                    break
                }
            }
        } else if let first = roots.first?.children.first {
            outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: first)), byExtendingSelection: false)
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
        (item as? OutlineItem)?.kind == .header ? 26 : 34
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? OutlineItem else { return nil }
        let id = NSUserInterfaceItemIdentifier("side")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? SidebarCell) ?? SidebarCell()
        cell.identifier = id
        let selected = outlineView.item(atRow: outlineView.selectedRow) as? OutlineItem === n
        cell.apply(title: n.title, image: icon(for: n), selected: selected, header: n.kind == .header)
        cell.toolTip = tooltip(for: n)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        outline.reloadData()
        showSelection()
    }

    private func showSelection() {
        let n = outline.item(atRow: outline.selectedRow) as? OutlineItem
        if n == nil || n?.kind == .header {
            titleLabel.stringValue = "Overview"
            subtitle.stringValue = "Tunnels, health, and version drift across every configured app."
            chartTitle.stringValue = "Fleet health"
            spark.values = store.fleetSpark
            bars.values = regionGroups(store.deploys).map { g in
                let ok = g.items.filter { $0.health == "healthy" }.count
                return (g.key, Double(ok), ok == g.items.count)
            }
            body.stringValue = "Tunnels \(store.tunnelsUp) of \(store.tunnels.count) up. \(store.healthyDeploys) of \(store.deploys.count) apps healthy. \(store.degradedDeploys) degraded, \(store.downDeploys) down, \(store.driftDeploys) version drift."
            return
        }
        switch n!.kind {
        case .header: break
        case .tunnel:
            guard let t = store.tunnels.first(where: { $0.id == n!.id }) else { return }
            titleLabel.stringValue = t.title
            subtitle.stringValue = t.up
                ? "Listening on \(t.host):\(t.port ?? 0). Process \(t.process ?? "unknown"), pid \(t.pid ?? "—"), up \(t.elapsed ?? "—")."
                : "Nothing is listening on \(t.host):\(t.port ?? 0). Start a forward or use Connect."
            chartTitle.stringValue = "Listen"
            spark.values = [t.up ? 1 : 0, t.up ? 1 : 0]
            bars.values = [("port", t.up ? 1 : 0, t.up)]
            body.stringValue = t.command ?? ""
        case .deploy:
            guard let d = store.deploys.first(where: { $0.id == n!.id }) else { return }
            titleLabel.stringValue = d.title
            let avg = d.avgMs.map { String(format: "%.0f ms", $0) } ?? "—"
            subtitle.stringValue = "\(d.health.capitalized). \(d.okCount) of \(d.checks.count) checks passing. Average latency \(avg)."
            chartTitle.stringValue = "Check latency"
            spark.values = d.spark
            bars.values = d.checks.map { ($0.name, $0.ms ?? 0, $0.status == "healthy") }
            if bars.values.isEmpty {
                bars.values = [("health", DeployRow.healthScore(d.health), d.up)]
            }
            var extra = "App \(d.liveVersion)  ·  deploy \(d.k8sVersion)  ·  pod \(d.k8sLiveVersion)"
            if let u = d.uptime { extra += String(format: "  ·  uptime %.1fs", u) }
            body.stringValue = extra
        }
    }

    private func icon(for n: OutlineItem) -> NSImage? {
        if n.kind == .tunnel, n.title.lowercased().contains("gitlab") {
            return NSImage(named: "GitLab")
                ?? Bundle.main.url(forResource: "GitLab", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        }
        let name: String
        switch n.kind {
        case .header: return nil
        case .tunnel: name = "network"
        case .deploy: name = n.title.lowercased().contains("prod") ? "server.rack" : "hammer"
        }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: n.title)
        img?.isTemplate = true
        return img
    }

    private func tooltip(for n: OutlineItem) -> String {
        switch n.kind {
        case .header: return n.title
        case .tunnel: return "TCP tunnel"
        case .deploy: return "App health"
        }
    }
}
