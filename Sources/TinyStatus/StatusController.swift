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

final class StatusController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let store = Store.shared
    private var bag = Set<AnyCancellable>()
    private var roots: [OutlineItem] = []
    private let outline = NSOutlineView()
    private let detail = NSTextView()
    private let spark = SparkView()
    private let detailTitle = NSTextField(labelWithString: "Select an item")
    private let metrics = NSTextField(labelWithString: "")

    override func loadView() {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin

        let sideScroll = NSScrollView()
        sideScroll.hasVerticalScroller = true
        sideScroll.borderType = .noBorder
        sideScroll.drawsBackground = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = "Name"
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.delegate = self
        outline.dataSource = self
        outline.allowsEmptySelection = false
        outline.rowSizeStyle = .default
        outline.style = .sourceList
        sideScroll.documentView = outline
        sideScroll.translatesAutoresizingMaskIntoConstraints = false

        let detailPane = NSView()
        detailTitle.font = .preferredFont(forTextStyle: .title2)
        metrics.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        metrics.textColor = .secondaryLabelColor
        metrics.maximumNumberOfLines = 3
        spark.translatesAutoresizingMaskIntoConstraints = false
        detail.isEditable = false
        detail.isRichText = false
        detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .secondaryLabelColor
        detail.backgroundColor = .clear
        detail.drawsBackground = false
        let detailScroll = NSScrollView()
        detailScroll.documentView = detail
        detailScroll.hasVerticalScroller = true
        detailScroll.borderType = .noBorder
        detailScroll.drawsBackground = false
        detailScroll.translatesAutoresizingMaskIntoConstraints = false

        for v in [detailTitle, metrics, spark, detailScroll] {
            v.translatesAutoresizingMaskIntoConstraints = false
            detailPane.addSubview(v)
        }
        NSLayoutConstraint.activate([
            detailTitle.topAnchor.constraint(equalTo: detailPane.topAnchor, constant: 16),
            detailTitle.leadingAnchor.constraint(equalTo: detailPane.leadingAnchor, constant: 16),
            detailTitle.trailingAnchor.constraint(equalTo: detailPane.trailingAnchor, constant: -16),
            metrics.topAnchor.constraint(equalTo: detailTitle.bottomAnchor, constant: 8),
            metrics.leadingAnchor.constraint(equalTo: detailTitle.leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: detailTitle.trailingAnchor),
            spark.topAnchor.constraint(equalTo: metrics.bottomAnchor, constant: 10),
            spark.leadingAnchor.constraint(equalTo: detailTitle.leadingAnchor),
            spark.trailingAnchor.constraint(equalTo: detailTitle.trailingAnchor),
            spark.heightAnchor.constraint(equalToConstant: 40),
            detailScroll.topAnchor.constraint(equalTo: spark.bottomAnchor, constant: 10),
            detailScroll.leadingAnchor.constraint(equalTo: detailPane.leadingAnchor, constant: 12),
            detailScroll.trailingAnchor.constraint(equalTo: detailPane.trailingAnchor, constant: -12),
            detailScroll.bottomAnchor.constraint(equalTo: detailPane.bottomAnchor, constant: -12),
        ])

        split.addSubview(sideScroll)
        split.addSubview(detailPane)
        view = split
        DispatchQueue.main.async {
            split.setPosition(220, ofDividerAt: 0)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &bag)
        reload()
    }

    func reload() {
        let selected = outline.item(atRow: outline.selectedRow) as? OutlineItem
        var items: [OutlineItem] = []
        if !store.tunnels.isEmpty {
            let t = OutlineItem(kind: .header, id: "h-tun", title: "Tunnels")
            t.children = store.tunnels.map { OutlineItem(kind: .tunnel, id: $0.id, title: $0.title) }
            items.append(t)
        }
        for g in regionGroups(store.deploys) {
            let n = OutlineItem(kind: .header, id: "h-\(g.key)", title: g.key)
            n.children = g.items.map { OutlineItem(kind: .deploy, id: $0.id, title: envLabel($0.title)) }
            items.append(n)
        }
        roots = items
        outline.reloadData()
        for r in roots { outline.expandItem(r) }
        if let selected {
            for r in roots {
                if let match = r.children.first(where: { $0.id == selected.id }) {
                    let row = outline.row(forItem: match)
                    if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
                    break
                }
            }
        } else if let first = roots.first?.children.first {
            outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: first)), byExtendingSelection: false)
        }
        showSelection()
        updateStatusItem()
    }

    private func updateStatusItem() {
        AppDelegate.instance?.setStatus(ok: store.allOK)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? OutlineItem)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? OutlineItem)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? OutlineItem)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? OutlineItem)?.kind == .header
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? OutlineItem else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let img = NSImageView()
            img.translatesAutoresizingMaskIntoConstraints = false
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            c.addSubview(img)
            c.addSubview(tf)
            c.imageView = img
            c.textField = tf
            NSLayoutConstraint.activate([
                img.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                img.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                img.widthAnchor.constraint(equalToConstant: 18),
                img.heightAnchor.constraint(equalToConstant: 18),
                tf.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        cell.textField?.stringValue = n.title
        cell.imageView?.image = icon(for: n)
        cell.toolTip = tooltip(for: n)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        showSelection()
    }

    private func showSelection() {
        guard let n = outline.item(atRow: outline.selectedRow) as? OutlineItem else {
            detailTitle.stringValue = "Overview"
            metrics.stringValue = overviewText()
            spark.values = store.fleetSpark
            detail.string = overviewText()
            return
        }
        switch n.kind {
        case .header:
            detailTitle.stringValue = n.title
            if n.id == "h-tun" {
                metrics.stringValue = "\(store.tunnelsUp) of \(store.tunnels.count) listening"
                spark.values = store.tunnels.map { $0.up ? 1 : 0 }
                detail.string = store.tunnels.map {
                    "\($0.title)  \($0.up ? "up" : "down")  \($0.host):\($0.port ?? 0)"
                }.joined(separator: "\n")
            } else {
                let items = store.deploys.filter { regionKey($0.title) == n.title }
                let ok = items.filter { $0.health == "healthy" }.count
                metrics.stringValue = "\(ok) of \(items.count) healthy"
                spark.values = items.flatMap(\.spark)
                detail.string = items.map { "\($0.title)  \($0.health)  app \($0.liveVersion)" }.joined(separator: "\n")
            }
        case .tunnel:
            guard let t = store.tunnels.first(where: { $0.id == n.id }) else { return }
            detailTitle.stringValue = t.title
            metrics.stringValue = t.up
                ? "Listening on \(t.host):\(t.port ?? 0)   pid \(t.pid ?? "—")   up \(t.elapsed ?? "—")"
                : "Nothing listening on \(t.host):\(t.port ?? 0)"
            spark.values = [t.up ? 1 : 0, t.up ? 1 : 0]
            var lines = [
                "Host    \(t.host)",
                "Port    \(t.port.map(String.init) ?? "—")",
                "State   \(t.up ? "listening" : "down")",
                "Process \(t.process ?? "—")",
                "PID     \(t.pid ?? "—")",
                "Up      \(t.elapsed ?? "—")",
            ]
            if let c = t.command { lines.append("SSH     \(c)") }
            detail.string = lines.joined(separator: "\n")
        case .deploy:
            guard let d = store.deploys.first(where: { $0.id == n.id }) else { return }
            detailTitle.stringValue = d.title
            let avg = d.avgMs.map { String(format: "%.0f ms", $0) } ?? "—"
            metrics.stringValue = "\(d.health)   checks \(d.okCount)/\(d.checks.count)   avg \(avg)"
            spark.values = d.spark
            var lines = [
                "Health      \(d.health)",
                "App live    \(d.liveVersion)",
                "k8s deploy  \(d.k8sVersion)",
                "k8s live    \(d.k8sLiveVersion)",
            ]
            if let u = d.uptime { lines.append(String(format: "Uptime      %.1fs", u)) }
            for c in d.checks {
                let ms = c.ms.map { String(format: "  %.0f ms", $0) } ?? ""
                lines.append("\(c.name)  \(c.status)\(ms)")
            }
            detail.string = lines.joined(separator: "\n")
        }
    }

    private func overviewText() -> String {
        "Tunnels \(store.tunnelsUp)/\(store.tunnels.count)   Healthy \(store.healthyDeploys)/\(store.deploys.count)   Degraded \(store.degradedDeploys)   Down \(store.downDeploys)   Drift \(store.driftDeploys)"
    }

    private func icon(for n: OutlineItem) -> NSImage? {
        if n.kind == .tunnel, n.title.lowercased().contains("gitlab") {
            return NSImage(named: "GitLab")
                ?? Bundle.main.url(forResource: "GitLab", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        }
        let name: String
        switch n.kind {
        case .header: name = regionIcon(n.title)
        case .tunnel: name = "network"
        case .deploy: name = n.title.lowercased().contains("prod") ? "server.rack" : "hammer"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: n.title)
    }

    private func tooltip(for n: OutlineItem) -> String {
        switch n.kind {
        case .header: return "\(n.title) group"
        case .tunnel: return "SSH / TCP tunnel"
        case .deploy: return "App health and versions"
        }
    }
}
