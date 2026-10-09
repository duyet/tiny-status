import AppKit
import Combine
import SwiftUI

/// Sidebar row → list filter.
enum SidebarScope: Equatable {
    case all, attention
    case kind(String)
    case tag(String)

    static let kinds = ["HTTP", "TCP", "Tunnels", "Commands"]

    /// Sidebar kind bucket. A TCP check with a `start` action is a tunnel.
    static func category(_ c: Check) -> String {
        switch c.kind {
        case .http: return "HTTP"
        case .command: return "Commands"
        case .tcp:
            let acts = c.resolvedActions().contains { $0.id == "start" || $0.id == "stop" }
            let tagged = (c.tags ?? []).contains { $0.lowercased() == "tunnel" }
            return acts || tagged ? "Tunnels" : "TCP"
        }
    }

    func matches(_ c: Check, attention: Bool) -> Bool {
        switch self {
        case .all: return true
        case .attention: return attention
        case let .kind(k): return Self.category(c) == k
        case let .tag(t): return Tags.resolved(c).contains(t)
        }
    }
}

enum Stats {
    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }

    /// Mean of history scores (1 up, 0.5 degraded, 0 down) as 0…1.
    static func uptime(_ spark: [Double]) -> Double? {
        spark.isEmpty ? nil : spark.reduce(0, +) / Double(spark.count)
    }
}

enum Motion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Window-level UI state: sidebar scope, selection, status-since, latency history.
@MainActor
final class MainState: ObservableObject {
    static let shared = MainState()

    @Published var scope: SidebarScope = .all
    @Published var selectedId: String?
    private(set) var since: [String: Date] = [:]
    private(set) var latency: [String: [Double]] = [:]
    private var word: [String: String] = [:]
    private var bag = Set<AnyCancellable>()

    init() {
        Store.shared.$lastChecked.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.record()
        }.store(in: &bag)
        NotificationCenter.default.publisher(for: TunnelLifecycle.didChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    func attention(_ id: String) -> Bool {
        let s = Store.shared
        if let t = s.tunnels.first(where: { $0.id == id }) { return t.enabled && !t.up && !t.busy }
        if let d = s.deploys.first(where: { $0.id == id }) {
            return d.enabled && d.health != "healthy" && d.health != "…"
        }
        return false
    }

    func statusWord(_ id: String) -> String {
        let s = Store.shared
        if let t = s.tunnels.first(where: { $0.id == id }) {
            return !t.enabled ? "OFF" : t.busy ? "CHECKING" : t.up ? "UP" : "DOWN"
        }
        if let d = s.deploys.first(where: { $0.id == id }) {
            if !d.enabled { return "OFF" }
            switch d.health {
            case "healthy": return "UP"
            case "degraded": return "DEGRADED"
            case "…": return "CHECKING"
            default: return "DOWN"
            }
        }
        return "—"
    }

    private func record() {
        let s = Store.shared
        let now = Date()
        for id in s.tunnels.map(\.id) + s.deploys.map(\.id) {
            let w = statusWord(id)
            if word[id] != w {
                word[id] = w
                since[id] = now
            }
        }
        for t in s.tunnels { if let ms = t.ms { push(t.id, ms) } }
        for d in s.deploys { if let ms = d.avgMs { push(d.id, ms) } }
    }

    private func push(_ id: String, _ ms: Double) {
        var xs = latency[id] ?? []
        xs.append(ms)
        latency[id] = Array(xs.suffix(40))
    }
}

/// Progress of the current poll. Separate from `Store` so ticks do not reload the table.
@MainActor
final class PollProgress: ObservableObject {
    static let shared = PollProgress()
    @Published private(set) var done = 0
    @Published private(set) var total = 0

    func begin(_ n: Int) {
        total = n
        done = 0
    }

    func tick() { done = min(total, done + 1) }
}

final class MainSplitController: NSSplitViewController {
    let status = StatusController()

    override func viewDidLoad() {
        super.viewDidLoad()
        let side = NSSplitViewItem(sidebarWithViewController: SidebarController())
        side.minimumThickness = 180
        side.maximumThickness = 280
        let content = NSSplitViewItem(viewController: status)
        content.minimumThickness = 420
        let host = NSHostingController(rootView: InspectorView(store: .shared, ui: .shared))
        let inspector = NSSplitViewItem(inspectorWithViewController: host)
        inspector.minimumThickness = 260
        inspector.maximumThickness = 380
        inspector.canCollapse = true
        addSplitViewItem(side)
        addSplitViewItem(content)
        addSplitViewItem(inspector)
        splitView.autosaveName = "TinyStatus.split"
    }
}

// MARK: - Sidebar

private final class SideItem: NSObject {
    let title: String
    let scope: SidebarScope?
    let symbol: String
    let count: Int
    let alert: Bool
    var children: [SideItem]

    init(_ title: String, scope: SidebarScope?, symbol: String = "", count: Int = 0, alert: Bool = false, children: [SideItem] = []) {
        self.title = title
        self.scope = scope
        self.symbol = symbol
        self.count = count
        self.alert = alert
        self.children = children
    }
}

final class SidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let outline = NSOutlineView()
    private var items: [SideItem] = []
    private var applying = false
    private var bag = Set<AnyCancellable>()

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("side"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.delegate = self
        outline.dataSource = self
        let ctx = NSMenu()
        ctx.delegate = self
        outline.menu = ctx
        scroll.documentView = outline

        let footer = NSHostingView(rootView: LinkFooter(link: .shared))
        footer.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(scroll)
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        LinkStatus.shared.start()
        Store.shared.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.reload()
        }.store(in: &bag)
        reload()
    }

    private func reload() {
        let store = Store.shared
        let ui = MainState.shared
        let checks = store.allChecks()
        let attention = checks.filter { $0.isEnabled && ui.attention($0.id) }.count
        let kinds = SidebarScope.kinds.compactMap { k -> SideItem? in
            let n = checks.filter { SidebarScope.category($0) == k }.count
            guard n > 0 || k == "Tunnels" else { return nil }
            let sym = ["HTTP": "globe", "TCP": "network", "Tunnels": "point.3.connected.trianglepath.dotted", "Commands": "terminal"][k] ?? "circle"
            return SideItem(k, scope: .kind(k), symbol: sym, count: n)
        }
        var tagCount: [String: Int] = [:]
        var tagOrder: [String] = []
        for c in checks {
            for t in Tags.resolved(c) {
                if tagCount[t] == nil { tagOrder.append(t) }
                tagCount[t, default: 0] += 1
            }
        }
        let tags = tagOrder.map { SideItem($0, scope: .tag($0), symbol: "tag", count: tagCount[$0] ?? 0) }
        items = [
            SideItem("All checks", scope: .all, symbol: "square.stack", count: checks.count),
            SideItem("Needs attention", scope: .attention, symbol: "exclamationmark.triangle", count: attention, alert: attention > 0),
            SideItem("Kinds", scope: nil, children: kinds),
        ]
        if !tags.isEmpty { items.append(SideItem("Tags", scope: nil, children: tags)) }
        applying = true
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        select(ui.scope)
        applying = false
    }

    private func select(_ scope: SidebarScope) {
        for r in 0 ..< outline.numberOfRows {
            if (outline.item(atRow: r) as? SideItem)?.scope == scope {
                outline.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
                return
            }
        }
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SideItem)?.children.count ?? items.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SideItem)?.children[index] ?? items[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? SideItem)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SideItem)?.scope == nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? SideItem)?.scope != nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let it = item as? SideItem else { return nil }
        if it.scope == nil {
            let tf = NSTextField(labelWithString: it.title)
            tf.font = .systemFont(ofSize: 11, weight: .semibold)
            tf.textColor = .secondaryLabelColor
            return tf
        }
        let id = NSUserInterfaceItemIdentifier("side-row")
        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? SideCell) ?? SideCell()
        cell.identifier = id
        cell.apply(it)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !applying, let it = outline.item(atRow: outline.selectedRow) as? SideItem, let scope = it.scope else { return }
        if MainState.shared.scope != scope { MainState.shared.scope = scope }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let it = outline.item(atRow: outline.clickedRow) as? SideItem, it.scope == .kind("Tunnels") else { return }
        let i = NSMenuItem(title: "New Tunnel…", action: #selector(AppDelegate.showNewTunnel), keyEquivalent: "")
        i.target = AppDelegate.instance
        menu.addItem(i)
    }
}

private final class SideCell: NSTableCellView {
    private let count = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let iv = NSImageView()
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        for v in [iv, tf, count] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        imageView = iv
        textField = tf
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        count.alignment = .right
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
            tf.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: tf.trailingAnchor, constant: 6),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    fileprivate func apply(_ it: SideItem) {
        textField?.stringValue = it.title
        imageView?.image = NSImage(systemSymbolName: it.symbol, accessibilityDescription: it.title)
        imageView?.contentTintColor = it.alert ? .systemRed : nil
        count.stringValue = "\(it.count)"
        count.textColor = it.alert ? .systemRed : .secondaryLabelColor
        setAccessibilityLabel("\(it.title), \(it.count)")
    }
}

private struct LinkFooter: View {
    @ObservedObject var link: LinkStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            chip(link.net.symbol, "\(link.net.title) · \(link.net.detail)", link.net.online)
            chip(link.tail.symbol, "\(link.tail.title) · \(link.tail.detail)", link.tail.up)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func chip(_ symbol: String, _ text: String, _ ok: Bool) -> some View {
        Label {
            Text(text).lineLimit(1).truncationMode(.tail)
        } icon: {
            Image(systemName: symbol).foregroundStyle(ok ? .green : .red)
        }
        .help(text)
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: MainState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let id = ui.selectedId, let check = store.allChecks().first(where: { $0.id == id }) {
                detail(check)
                    .id(id)
                    .transition(.opacity)
            } else {
                Text("Select a check to see details")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: ui.selectedId)
    }

    private func detail(_ c: Check) -> some View {
        let word = ui.statusWord(c.id)
        let tunnel = SidebarScope.category(c) == "Tunnels"
        let life = TunnelLifecycle.shared.state(for: c.id)
        let t = store.tunnels.first { $0.id == c.id }
        let d = store.deploys.first { $0.id == c.id }
        let spark = t?.spark ?? d?.spark ?? []
        let up = t?.up ?? d?.up ?? false
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(statusLine(word, since: ui.since[c.id]))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(word))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: word)
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                    Text("\(target(c)) · \(tunnel ? "Tunnel" : c.kind.rawValue.uppercased())")
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if tunnel {
                    tunnelControls(c, life: life)
                } else {
                    actionRow(c, up: up)
                }
                if let err = error(c, life: life, d: d) {
                    Text(err)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    row("Uptime", Stats.uptime(spark).map { String(format: "%.1f%% of %d polls", $0 * 100, spark.count) } ?? "—")
                    row("Median latency", Stats.median(ui.latency[c.id] ?? []).map { String(format: "%.0f ms", $0) } ?? "—")
                    if c.kind == .tcp {
                        row("Process", t?.process.map { p in t?.pid.map { "\(p) (\($0))" } ?? p } ?? "—")
                    }
                    if let v = d?.liveVersion, v != "—", v != "…" { row("Version", v) }
                    row("Alerts", AlertCenter.shared.statusText(c, global: store.alertsConfig))
                }
                .font(.callout)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func tunnelControls(_ c: Check, life: TunnelState) -> some View {
        let on: Bool = {
            switch life {
            case .starting, .connected: return true
            case .failed: return false
            case .stopped: return store.tunnels.first { $0.id == c.id }?.up ?? false
            }
        }()
        HStack {
            Toggle("Tunnel", isOn: Binding(
                get: { on },
                set: { $0 ? TunnelLifecycle.shared.start(c) : TunnelLifecycle.shared.stop(c) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            Text(TunnelLifecycle.text(life, port: c.port)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
        }
        HStack {
            if case let .failed(code, stderr) = life {
                Button("Retry") { TunnelLifecycle.shared.retry(c) }.buttonStyle(.borderedProminent)
                Button("Show log") { showLog(c.title, "exit \(code)\n\n\(stderr)") }
            }
            Button("Check now") { store.poll() }
        }
    }

    private func actionRow(_ c: Check, up: Bool) -> some View {
        HStack {
            if let a = c.resolvedActions().first(where: { $0.isVisible(up: up) }) {
                Button(a.title) { store.runAction(checkId: c.id, actionId: a.id) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Check now") { store.poll() }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).monospacedDigit().textSelection(.enabled)
        }
    }

    private func statusLine(_ word: String, since: Date?) -> String {
        guard let since else { return word }
        return "\(word) · \(TunnelLifecycle.uptime(Date().timeIntervalSince(since)))"
    }

    private func color(_ word: String) -> Color {
        switch word {
        case "UP": .green
        case "DOWN": .red
        case "DEGRADED": .orange
        default: .secondary
        }
    }

    private func target(_ c: Check) -> String {
        switch c.kind {
        case .http: c.openUrl ?? c.url ?? ""
        case .tcp: "\(c.host ?? "127.0.0.1"):\(c.port.map(String.init) ?? "?")"
        case .command: (c.command ?? []).joined(separator: " ")
        }
    }

    private func error(_ c: Check, life: TunnelState, d: DeployRow?) -> String? {
        if case let .failed(code, stderr) = life {
            return stderr.isEmpty ? "exit \(code)" : "exit \(code): \(stderr)"
        }
        guard let d, d.enabled, d.health != "healthy", d.health != "…" else { return nil }
        let bad = d.checks.filter { $0.status != "healthy" }.map { "\($0.name): \($0.status)" }
        return bad.isEmpty ? "health: \(d.health)" : bad.joined(separator: "\n")
    }

    private func showLog(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = "\(title) log"
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
        tv.string = text
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let sv = NSScrollView(frame: tv.frame)
        sv.hasVerticalScroller = true
        sv.documentView = tv
        a.accessoryView = sv
        a.runModal()
    }
}
