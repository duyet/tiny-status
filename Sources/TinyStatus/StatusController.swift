import AppKit
import Combine

private enum Col: String, CaseIterable {
    case status, name, kind, history, latency, target
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
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 6, height: 0)
        table.doubleAction = #selector(openRow)
        table.target = self
        table.autosaveName = "TinyStatus.checks"
        table.autosaveTableColumns = true

        addCol(.status, "", 28, min: 24, max: 36)
        addCol(.name, "Check", 200, min: 120, max: 400)
        addCol(.kind, "Type", 56, min: 48, max: 80)
        addCol(.history, "History", 176, min: 120, max: 280)
        addCol(.latency, "Latency", 72, min: 60, max: 100)
        addCol(.target, "Target", 260, min: 120, max: 2000)
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
        var all: [CheckListRow] = []
        for t in store.tunnels {
            let target = t.port.map { "\(t.host):\($0)" } ?? t.host
            let lat = t.ms.map { String(format: "%.0f ms", $0) } ?? "—"
            all.append(CheckListRow(
                id: t.id, title: t.title, kind: "TCP",
                status: t.busy ? "Checking" : (t.up ? "Up" : "Down"),
                ok: t.up, warn: false,
                spark: t.spark, latency: lat, target: target, url: nil
            ))
        }
        for d in store.deploys {
            let kids = d.checks
            if kids.isEmpty {
                all.append(listRow(deploy: d, check: nil))
            } else {
                for c in kids { all.append(listRow(deploy: d, check: c)) }
            }
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

    private func listRow(deploy d: DeployRow, check: CheckRow?) -> CheckListRow {
        let c = check
        let statusRaw = c?.status ?? d.health
        let warn = statusRaw == "degraded"
        let ok = statusRaw == "healthy"
        let checking = d.health == "…" && c == nil
        let lat = (c?.ms ?? d.avgMs).map { String(format: "%.0f ms", $0) } ?? "—"
        let title = c == nil ? d.title : "\(d.title) · \(c!.name)"
        return CheckListRow(
            id: c == nil ? d.id : "\(d.id)/\(c!.name)",
            title: title,
            kind: "HTTP",
            status: checking ? "Checking" : ok ? "Up" : warn ? "Degraded" : "Down",
            ok: ok, warn: warn,
            spark: c?.spark ?? d.spark,
            latency: lat,
            target: d.openUrl ?? "",
            url: d.openUrl
        )
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
        case .status:
            let cell = iconCell(tableView, id: "status")
            cell.textField?.isHidden = true
            cell.imageView?.image = statusImage(r)
            cell.toolTip = r.status
            return cell
        case .name:
            let cell = iconCell(tableView, id: "name")
            cell.textField?.isHidden = false
            cell.textField?.stringValue = r.title
            cell.textField?.font = .systemFont(ofSize: 13)
            cell.textField?.textColor = .labelColor
            cell.imageView?.image = NSImage(systemSymbolName: r.kind == "TCP" ? "network" : "globe", accessibilityDescription: r.kind)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = r.title
            return cell
        case .kind:
            let cell = textCell(tableView, id: "kind")
            cell.textField?.stringValue = r.kind
            cell.textField?.font = .systemFont(ofSize: 12)
            cell.textField?.textColor = .secondaryLabelColor
            return cell
        case .history:
            let id = NSUserInterfaceItemIdentifier("history")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? HistoryCell) ?? HistoryCell()
            cell.identifier = id
            cell.apply(r.spark)
            return cell
        case .latency:
            let cell = textCell(tableView, id: "lat")
            cell.textField?.stringValue = r.latency
            cell.textField?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.alignment = .right
            return cell
        case .target:
            let cell = textCell(tableView, id: "tgt")
            cell.textField?.stringValue = r.target
            cell.textField?.font = .systemFont(ofSize: 12)
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.lineBreakMode = .byTruncatingMiddle
            cell.toolTip = r.target
            return cell
        }
    }

    private func statusImage(_ r: CheckListRow) -> NSImage? {
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

    private func iconCell(_ tableView: NSTableView, id: String) -> NSTableCellView {
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
            iv.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
            iv.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
            tf.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    private func textCell(_ tableView: NSTableView, id: String) -> NSTableCellView {
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
