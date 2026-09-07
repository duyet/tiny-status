import AppKit
import Combine

private enum Col: String {
    case name, kind, status, history, latency, target
}

struct CheckListRow {
    var id: String
    var title: String
    var kind: String
    var status: String
    var ok: Bool
    var warn: Bool
    var spark: [Double]
    var latency: String
    var target: String
    var url: String?
}

final class StatusController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let search = NSSearchField()
    private let store = Store.shared
    private var bag = Set<AnyCancellable>()
    private var rows: [CheckListRow] = []
    private var filter = ""
    private let table = NSTableView()
    private let empty = NSTextField(labelWithString: "No checks yet.\nImport a host or paste JSON from TinyStatus → Import checks…")

    override func loadView() {
        search.placeholderString = "Filter"
        search.delegate = self
        search.focusRingType = .none
        search.sendsWholeSearchString = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        table.headerView = NSTableHeaderView()
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 44
        table.usesAlternatingRowBackgroundColors = false
        table.allowsColumnReordering = true
        table.allowsEmptySelection = true
        table.style = .inset
        table.gridStyleMask = []
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 8, height: 2)
        table.doubleAction = #selector(openRow)
        table.target = self
        addCol(.name, "Check", 200, min: 120)
        addCol(.kind, "Type", 64, min: 52)
        addCol(.status, "Status", 112, min: 96)
        addCol(.history, "History", 180, min: 132)
        addCol(.latency, "Latency", 72, min: 60)
        addCol(.target, "Target", 240, min: 100)
        scroll.documentView = table

        empty.font = .systemFont(ofSize: 13)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.maximumNumberOfLines = 3
        empty.isHidden = true
        empty.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.wantsLayer = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        root.addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])
        view = root
    }

    private func addCol(_ id: Col, _ title: String, _ w: CGFloat, min: CGFloat) {
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.rawValue))
        c.title = title
        c.width = w
        c.minWidth = min
        c.headerCell.alignment = .left
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
        var all: [CheckListRow] = []
        for t in store.tunnels {
            let target = t.port.map { "\(t.host):\($0)" } ?? t.host
            all.append(CheckListRow(
                id: t.id, title: t.title, kind: "TCP",
                status: t.up ? "Up" : "Down", ok: t.up, warn: false,
                spark: t.spark, latency: "—", target: target, url: nil
            ))
        }
        for d in store.deploys {
            let warn = d.health == "degraded"
            let ok = d.health == "healthy"
            let lat = d.avgMs.map { String(format: "%.0f ms", $0) } ?? "—"
            all.append(CheckListRow(
                id: d.id, title: d.title, kind: "HTTP",
                status: ok ? "Up" : warn ? "Degraded" : (d.health == "…" ? "Checking" : "Down"),
                ok: ok, warn: warn, spark: d.spark, latency: lat,
                target: d.openUrl ?? "", url: d.openUrl
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
        empty.isHidden = !all.isEmpty
        table.reloadData()
        let up = all.filter(\.ok).count
        view.window?.subtitle = all.isEmpty ? "" : "\(up) of \(all.count) up · \(store.lastCheckedLabel)"
        AppDelegate.instance?.setStatus(ok: store.allOK)
    }

    @objc private func openRow() {
        let i = table.clickedRow
        guard i >= 0, i < rows.count, let s = rows[i].url, let u = URL(string: s) else { return }
        NSWorkspace.shared.open(u)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count, let raw = tableColumn?.identifier.rawValue, let col = Col(rawValue: raw) else { return nil }
        let r = rows[row]
        switch col {
        case .name:
            let id = NSUserInterfaceItemIdentifier("name")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? LabelCell) ?? LabelCell()
            cell.identifier = id
            cell.apply(r.title, font: .systemFont(ofSize: 13, weight: .medium), color: .labelColor)
            return cell
        case .kind:
            let id = NSUserInterfaceItemIdentifier("kind")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? LabelCell) ?? LabelCell()
            cell.identifier = id
            cell.apply(r.kind, font: .systemFont(ofSize: 12, weight: .medium), color: .tertiaryLabelColor)
            return cell
        case .status:
            let id = NSUserInterfaceItemIdentifier("status")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? StatusCell) ?? StatusCell()
            cell.identifier = id
            cell.apply(r)
            return cell
        case .history:
            let id = NSUserInterfaceItemIdentifier("history")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? HistoryCell) ?? HistoryCell()
            cell.identifier = id
            cell.apply(r.spark)
            return cell
        case .latency:
            let id = NSUserInterfaceItemIdentifier("lat")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? LabelCell) ?? LabelCell()
            cell.identifier = id
            cell.apply(r.latency, font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor)
            return cell
        case .target:
            let id = NSUserInterfaceItemIdentifier("tgt")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? LabelCell) ?? LabelCell()
            cell.identifier = id
            cell.apply(r.target, font: .systemFont(ofSize: 12), color: .tertiaryLabelColor)
            return cell
        }
    }
}

private final class LabelCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ s: String, font: NSFont, color: NSColor) {
        label.stringValue = s
        label.font = font
        label.textColor = color
        toolTip = s
    }
}

private final class StatusCell: NSTableCellView {
    private let pill = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var ok = false
    private var warn = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 11
        pill.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)
        pill.addSubview(icon)
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 22),
            icon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            icon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 11),
            icon.heightAnchor.constraint(equalToConstant: 11),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ r: CheckListRow) {
        ok = r.ok
        warn = r.warn
        label.stringValue = r.status
        let name = r.warn ? "exclamationmark.circle.fill" : r.ok ? "checkmark.circle.fill" : r.status == "Checking" ? "ellipsis.circle.fill" : "xmark.circle.fill"
        icon.image = NSImage(systemSymbolName: name, accessibilityDescription: r.status)
        icon.contentTintColor = tint()
        label.textColor = tint()
        paint()
    }

    private func tint() -> NSColor {
        warn ? .systemOrange : ok ? .systemGreen : label.stringValue == "Checking" ? .secondaryLabelColor : .systemRed
    }

    private func paint() {
        pill.layer?.backgroundColor = tint().withAlphaComponent(effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.22 : 0.14).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
        icon.contentTintColor = tint()
        label.textColor = tint()
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
            beat.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            beat.centerYAnchor.constraint(equalTo: centerYAnchor),
            beat.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ spark: [Double]) {
        beat.values = spark
        toolTip = spark.isEmpty ? "No history yet" : "Last \(spark.count) checks"
    }
}
