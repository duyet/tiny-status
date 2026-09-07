import AppKit
import Combine

private enum Col: String {
    case name, kind, status, history, latency, target
}

private struct Row {
    var id: String
    var title: String
    var kind: String
    var status: String
    var ok: Bool
    var warn: Bool
    var spark: [Double]
    var latency: String
    var target: String
}

final class StatusController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store = Store.shared
    private var bag = Set<AnyCancellable>()
    private var rows: [Row] = []
    private var filter = ""
    private let table = NSTableView()
    private let search = NSSearchField()
    private let summary = NSTextField(labelWithString: "")

    override func loadView() {
        let root = NSView()
        search.placeholderString = "Filter checks"
        search.delegate = self
        search.focusRingType = .none
        search.translatesAutoresizingMaskIntoConstraints = false
        summary.font = .systemFont(ofSize: 12)
        summary.textColor = .secondaryLabelColor
        summary.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        table.headerView = NSTableHeaderView()
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 36
        table.usesAlternatingRowBackgroundColors = true
        table.allowsColumnReordering = false
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .regular
        table.style = .fullWidth
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.gridColor = NSColor.separatorColor.withAlphaComponent(0.25)
        addCol(.name, "Check", 180, min: 120)
        addCol(.kind, "Type", 88, min: 72)
        addCol(.status, "Status", 110, min: 88)
        addCol(.history, "History", 168, min: 120)
        addCol(.latency, "Latency", 80, min: 64)
        addCol(.target, "Target", 220, min: 100)
        scroll.documentView = table

        root.addSubview(search)
        root.addSubview(summary)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 10),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            search.widthAnchor.constraint(equalToConstant: 220),
            summary.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            summary.leadingAnchor.constraint(equalTo: search.trailingAnchor, constant: 12),
            summary.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    private func addCol(_ id: Col, _ title: String, _ w: CGFloat, min: CGFloat) {
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.rawValue))
        c.title = title
        c.width = w
        c.minWidth = min
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
        var all: [Row] = []
        for t in store.tunnels {
            let target = t.port.map { "\(t.host):\($0)" } ?? t.host
            all.append(Row(
                id: t.id, title: t.title, kind: "TCP",
                status: t.up ? "Up" : "Down", ok: t.up, warn: false,
                spark: t.spark, latency: "—", target: target
            ))
        }
        for d in store.deploys {
            let warn = d.health == "degraded"
            let ok = d.health == "healthy"
            let lat = d.avgMs.map { String(format: "%.0f ms", $0) } ?? "—"
            all.append(Row(
                id: d.id, title: d.title, kind: "HTTP",
                status: ok ? "Up" : warn ? "Degraded" : (d.health == "…" ? "…" : "Down"),
                ok: ok, warn: warn, spark: d.spark, latency: lat,
                target: d.openUrl ?? ""
            ))
        }
        if !filter.isEmpty {
            all = all.filter {
                $0.title.lowercased().contains(filter)
                    || $0.kind.lowercased().contains(filter)
                    || $0.target.lowercased().contains(filter)
                    || $0.status.lowercased().contains(filter)
            }
        }
        rows = all
        table.reloadData()
        let up = all.filter(\.ok).count
        summary.stringValue = "\(up) of \(all.count) up"
        if let last = store.lastCheckedLabel as String? { summary.stringValue += "  ·  \(last)" }
        AppDelegate.instance?.setStatus(ok: store.allOK)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count, let id = tableColumn?.identifier.rawValue, let col = Col(rawValue: id) else { return nil }
        let r = rows[row]
        switch col {
        case .name:
            return textCell(r.title, font: .systemFont(ofSize: 13, weight: .medium))
        case .kind:
            return badgeCell(r.kind)
        case .status:
            return statusCell(r)
        case .history:
            return historyCell(r.spark)
        case .latency:
            return textCell(r.latency, font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor)
        case .target:
            return textCell(r.target, font: .systemFont(ofSize: 12), color: .tertiaryLabelColor)
        }
    }

    private func textCell(_ s: String, font: NSFont, color: NSColor = .labelColor) -> NSTableCellView {
        let v = NSTableCellView()
        let t = NSTextField(labelWithString: s)
        t.font = font
        t.textColor = color
        t.lineBreakMode = .byTruncatingMiddle
        t.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(t)
        v.textField = t
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
            t.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
            t.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    private func badgeCell(_ s: String) -> NSView {
        let wrap = NSTableCellView()
        let t = NSTextField(labelWithString: s)
        t.font = .systemFont(ofSize: 11, weight: .medium)
        t.textColor = .secondaryLabelColor
        t.alignment = .center
        t.wantsLayer = true
        t.drawsBackground = true
        t.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.18)
        t.layer?.cornerRadius = 8
        t.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(t)
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 4),
            t.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            t.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
            t.heightAnchor.constraint(equalToConstant: 20),
        ])
        return wrap
    }

    private func statusCell(_ r: Row) -> NSView {
        let wrap = NSTableCellView()
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = (r.warn ? NSColor.systemOrange : r.ok ? NSColor.systemGreen : NSColor.systemRed).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        let t = NSTextField(labelWithString: r.status)
        t.font = .systemFont(ofSize: 12, weight: .medium)
        t.textColor = r.warn ? .systemOrange : r.ok ? .systemGreen : .systemRed
        t.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(dot)
        wrap.addSubview(t)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            t.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            t.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
        ])
        return wrap
    }

    private func historyCell(_ spark: [Double]) -> NSView {
        let wrap = NSTableCellView()
        let h = HeartbeatView()
        h.values = spark
        h.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(h)
        NSLayoutConstraint.activate([
            h.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 4),
            h.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -8),
            h.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            h.heightAnchor.constraint(equalToConstant: 16),
        ])
        return wrap
    }
}
