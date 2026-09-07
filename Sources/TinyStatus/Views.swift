import AppKit
import SwiftUI

struct BarLabel: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        Image(systemName: store.barSymbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(store.barColor)
            .accessibilityLabel("TinyStatus")
    }
}

enum Palette {
    static let gitlab = Color(red: 0.99, green: 0.43, blue: 0.15)
    static let sg = Color(red: 0.10, green: 0.72, blue: 0.64)
    static let eu = Color(red: 0.28, green: 0.48, blue: 0.98)
    static let za = Color(red: 0.95, green: 0.72, blue: 0.12)
    static let app = Color(red: 0.35, green: 0.55, blue: 1.0)
    static let deploy = Color(red: 0.62, green: 0.40, blue: 0.98)
    static let pod = Color(red: 0.20, green: 0.78, blue: 0.55)

    static func region(_ key: String) -> Color {
        switch regionKey(key) {
        case "SG": sg
        case "EU": eu
        case "ZA": za
        default: .purple
        }
    }

    static func health(_ s: String) -> Color {
        switch s {
        case "healthy": .green
        case "degraded": .orange
        default: .red
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content }
}

struct Mark: View {
    var ok: Bool
    var warn: Bool = false
    var label: String? = nil
    var body: some View {
        Image(systemName: warn ? "exclamationmark.circle.fill" : ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(warn ? Color.orange : ok ? Color.green : Color.red)
            .imageScale(.small)
            .symbolRenderingMode(.hierarchical)
            .help(label ?? (warn ? "Degraded" : ok ? "OK" : "Down"))
    }
}

struct IconBtn: View {
    var system: String
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
        }
        .help(help)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct Line: View {
    var icon: String
    var label: String
    var value: String
    var ok: Bool
    var warn: Bool = false
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(warn ? Color.orange : ok ? Color.green : Color.red)
                .frame(width: 12)
                .imageScale(.small)
                .help("\(label): \(value)")
            Text(label)
            Spacer(minLength: 6)
            Text(value)
                .foregroundStyle(warn ? Color.orange : ok ? Color.primary : Color.red)
                .lineLimit(1)
                .truncationMode(.middle)
            Mark(ok: ok, warn: warn)
        }
        .font(.caption)
    }
}

struct Spark: View {
    var values: [Double]
    var wide: Bool = false
    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height * (1 - CGFloat(min(1, max(0, v))))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            let last = values.last ?? 0
            let color: Color = last >= 0.99 ? .green : last >= 0.4 ? .orange : .red
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(color.opacity(0.22)))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        .frame(minWidth: wide ? 80 : 56, idealWidth: wide ? 240 : 56, maxWidth: wide ? .infinity : 56, minHeight: wide ? 52 : 16, maxHeight: wide ? 52 : 16)
        .help("Health over the last \(max(values.count, 0)) checks (green up, orange degraded, red down)")
        .accessibilityLabel("Health history")
    }

    static func score(_ health: String) -> Double {
        switch health {
        case "healthy": 1
        case "degraded": 0.5
        default: 0
        }
    }
}

struct MetricChip: View {
    var icon: String
    var title: String
    var value: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("\(title): \(value)")
    }
}

struct LatencyChart: View {
    var checks: [CheckRow]
    var body: some View {
        let maxMs = max(checks.compactMap(\.ms).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            Text("Latency")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(checks) { c in
                HStack(spacing: 6) {
                    Image(systemName: checkIcon(c.name))
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.health(c.status))
                        .frame(width: 12)
                        .help("\(c.name): \(c.status)")
                    Text(c.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .frame(width: 88, alignment: .leading)
                    GeometryReader { g in
                        let w = g.size.width * CGFloat((c.ms ?? 0) / maxMs)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Palette.health(c.status))
                            .frame(width: max(w, 3), height: 8)
                    }
                    .frame(height: 8)
                    Text(c.ms.map { String(format: "%.0f ms", $0) } ?? "—")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}

struct CheckDots: View {
    var checks: [CheckRow]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(checks) { c in
                Image(systemName: checkIcon(c.name))
                    .font(.system(size: 9))
                    .foregroundStyle(
                        c.status == "healthy" ? Color.green
                            : c.status == "degraded" ? Color.orange : Color.red
                    )
                    .help("\(c.name): \(c.status)\n\(checkHint(c.name))")
            }
        }
    }
}

struct VersionBar: View {
    var app: String
    var deploy: String
    var live: String
    var body: some View {
        HStack(spacing: 4) {
            pill("iphone", app, Palette.app, deploy == app && live == app,
                 "App live: version from HTTP /health")
            pill("shippingbox", deploy, Palette.deploy, deploy == live,
                 "k8s deploy: desired image tag on the Deployment")
            pill("memorychip", live, Palette.pod, live == app,
                 "k8s live: image tag on the running pod")
        }
    }

    private func pill(_ icon: String, _ value: String, _ tint: Color, _ ok: Bool, _ tip: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).imageScale(.small)
            Text(value).font(.caption2.monospaced())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .foregroundStyle(ok ? Color.primary : Color.secondary)
        .help("\(tip)\n\(value)\(ok ? " — matches" : " — drift")")
    }
}

func regionIcon(_ title: String) -> String {
    let t = title.lowercased()
    if t.contains("gitlab") { return "network" }
    if t.contains("ssh") || t.contains("tunnel") { return "lock.shield" }
    if t.hasPrefix("sg") { return "globe.asia.australia.fill" }
    if t.hasPrefix("eu") { return "globe.europe.africa.fill" }
    if t.hasPrefix("za") { return "globe" }
    if t.contains("prod") { return "server.rack" }
    if t.contains("dev") { return "hammer" }
    return "app"
}

func gitlabImage() -> NSImage? {
    NSImage(named: "GitLab")
        ?? Bundle.main.url(forResource: "GitLab", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
}

struct BrandIcon: View {
    var title: String
    var body: some View {
        Group {
            if title.lowercased().contains("gitlab"), let img = gitlabImage() {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: regionIcon(title))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 20, height: 20)
        .help(title.lowercased().contains("gitlab")
            ? "GitLab HTTPS tunnel"
            : "\(title)")
    }
}

func checkHint(_ name: String) -> String {
    let n = name.lowercased()
    if n.contains("data") || n.contains("postgres") { return "Database connectivity" }
    if n.contains("cache") || n.contains("redis") { return "Cache / Redis" }
    if n.contains("vector") || n.contains("qdrant") { return "Vector database" }
    if n.contains("click") || n.contains("analytics") { return "Analytics store" }
    if n.contains("llm") || n.contains("openrouter") { return "LLM provider" }
    if n.contains("api") { return "API route" }
    if n.contains("migrat") { return "Schema migrations" }
    return "Health check"
}

func regionKey(_ title: String) -> String {
    let head = title.split(separator: " ").first.map(String.init)?.uppercased() ?? title.uppercased()
    if ["SG", "EU", "ZA", "US", "UK"].contains(head) { return head }
    return "Other"
}

func envLabel(_ title: String) -> String {
    let rest = title.split(separator: " ").dropFirst().joined(separator: " ")
    return rest.isEmpty ? title : rest
}

func envRank(_ title: String) -> Int {
    let t = title.lowercased()
    if t.contains("dev") { return 0 }
    if t.contains("staging") { return 1 }
    if t.contains("prod") { return 2 }
    return 3
}

struct RegionGroup: Identifiable {
    var id: String { key }
    var key: String
    var items: [DeployRow]
}

func regionGroups(_ deploys: [DeployRow]) -> [RegionGroup] {
    var map: [String: [DeployRow]] = [:]
    for d in deploys {
        map[regionKey(d.title), default: []].append(d)
    }
    for k in map.keys {
        map[k]?.sort { envRank($0.title) < envRank($1.title) }
    }
    let order = ["SG", "EU", "ZA"]
    var out: [RegionGroup] = []
    for k in order where map[k]?.isEmpty == false {
        out.append(RegionGroup(key: k, items: map[k]!))
    }
    for k in map.keys.sorted() where !order.contains(k) {
        out.append(RegionGroup(key: k, items: map[k]!))
    }
    return out
}

func checkIcon(_ name: String) -> String {
    let n = name.lowercased()
    if n.contains("data") || n.contains("postgres") { return "cylinder.split.1x2" }
    if n.contains("cache") || n.contains("redis") { return "bolt.fill" }
    if n.contains("vector") || n.contains("qdrant") { return "square.stack.3d.up" }
    if n.contains("click") || n.contains("analytics") { return "chart.bar" }
    if n.contains("llm") || n.contains("openrouter") { return "sparkles" }
    if n.contains("api") { return "point.3.connected.trianglepath.dotted" }
    if n.contains("migrat") { return "arrow.triangle.2.circlepath" }
    return "circle.fill"
}

struct ConfigWindow: View {
    @ObservedObject var store: Store

    var body: some View {
        Form {
            Section {
                ForEach(store.allChecks()) { c in
                    CheckConfigDetail(check: c, store: store)
                }
            } header: {
                Label("Checks (\(store.allChecks().count))", systemImage: "list.bullet")
            } footer: {
                Text("Click a check to see config and the last live probe. Edit JSON below to change fields, then Save.")
            }
            Section {
                TextField("Poll seconds", value: $store.editPollSeconds, format: .number)
                LabeledContent("Last poll") {
                    Text(store.lastCheckedLabel)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Schedule", systemImage: "timer")
            }
            Section {
                Toggle(isOn: $store.editAlertsEnabled) { Label("Enabled", systemImage: "bell") }
                Toggle(isOn: $store.editOnDown) { Label("On down", systemImage: "xmark.octagon") }
                Toggle(isOn: $store.editOnRecover) { Label("On recover", systemImage: "checkmark.seal") }
                Toggle(isOn: $store.editOnDrift) { Label("On version drift", systemImage: "arrow.left.arrow.right") }
                TextField("Cooldown seconds", value: $store.editCooldown, format: .number)
            } header: {
                Label("Alerts", systemImage: "bell.badge")
            }
            Section {
                LabeledContent("Path") {
                    Text(ConfigLoader.userURL.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigLoader.userURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            } header: {
                Label("File", systemImage: "internaldrive")
            }
            Section {
                Toggle(isOn: $store.editBackupEnabled) { Label("Enabled", systemImage: "externaldrive.badge.checkmark") }
                Toggle(isOn: $store.editBackupAuto) { Label("Backup on Save", systemImage: "clock.arrow.circlepath") }
                TextField("Repo folder", text: $store.editBackupRepo)
                TextField("File in repo", text: $store.editBackupFile)
                TextField("Remote", text: $store.editBackupRemote)
                TextField("Branch", text: $store.editBackupBranch)
                TextField("Clone URL", text: $store.editBackupRemoteUrl)
                HStack {
                    Button { store.gitBackup() } label: { Label("Backup", systemImage: "square.and.arrow.up") }
                    Button { store.gitPull() } label: { Label("Pull", systemImage: "square.and.arrow.down") }
                    Button { store.gitSync() } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.gitBusy || !store.editBackupEnabled)
                if store.gitConflict {
                    HStack {
                        Button { store.gitKeepLocal() } label: { Label("Keep local", systemImage: "desktopcomputer") }
                        Button { store.gitKeepRemote() } label: { Label("Keep remote", systemImage: "cloud") }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                if !store.gitLog.isEmpty {
                    Text(store.gitLog)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            } header: {
                Label("Git backup", systemImage: "externaldrive.badge.icloud")
            }
            Section {
                TextEditor(text: $store.configText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
            } header: {
                Label("JSON", systemImage: "curlybraces")
            }
            if let error = store.configError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 640, minHeight: 640)
        .onAppear { store.loadConfigEditor() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { store.saveConfig() } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct CheckConfigDetail: View {
    var check: Check
    @ObservedObject var store: Store

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                kv("ID", check.id)
                kv("Kind", check.kind.rawValue.uppercased())
                if let u = check.url { kv("Health URL", u) }
                if let h = check.host {
                    kv("Host", check.port.map { "\(h):\($0)" } ?? h)
                }
                if let u = check.openUrl { kv("Open URL", u) }
                if check.discover == true { kv("Discover", "auto-find health paths") }
                cmd("Start", check.start)
                cmd("Stop", check.stop)
                cmd("Open", check.open)
                cmd("Command", check.command)
                cmd("kubectl deploy", check.k8s)
                cmd("kubectl live", check.k8sLive)
                liveBlock
            }
            .padding(.vertical, 6)
        } label: {
            Label {
                HStack {
                    Text(check.title)
                    Spacer()
                    Text(liveLabel)
                        .font(.caption)
                        .foregroundStyle(liveColor)
                    Text(check.kind.rawValue.uppercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: check.kind == .tcp ? "network" : check.kind == .http ? "globe" : "terminal")
            }
        }
    }

    @ViewBuilder private var liveBlock: some View {
        if let t = store.tunnels.first(where: { $0.id == check.id }) {
            Divider()
            Text("Last probe").font(.caption).foregroundStyle(.secondary)
            kv("State", t.up ? "Listening" : "Not listening")
            if let ms = t.ms { kv("Connect", String(format: "%.0f ms", ms)) }
            if let p = t.process { kv("Process", p) }
            if let pid = t.pid { kv("PID", pid) }
            if let e = t.elapsed { kv("Uptime", e) }
            if let c = t.command { kv("Command line", c) }
        }
        if let d = store.deploys.first(where: { $0.id == check.id }) {
            Divider()
            Text("Last probe").font(.caption).foregroundStyle(.secondary)
            kv("Health", d.health)
            kv("App version", d.liveVersion)
            kv("Deploy image", d.k8sVersion)
            kv("Pod image", d.k8sLiveVersion)
            if let u = d.uptime { kv("Uptime", String(format: "%.1fs", u)) }
            if let avg = d.avgMs { kv("Avg latency", String(format: "%.0f ms", avg)) }
            if !d.checks.isEmpty {
                Text("Services").font(.caption).foregroundStyle(.secondary)
                ForEach(d.checks) { c in
                    HStack {
                        Image(systemName: checkIcon(c.name))
                            .foregroundStyle(Palette.health(c.status))
                            .frame(width: 14)
                        Text(c.name)
                        Spacer()
                        Text(c.status)
                            .foregroundStyle(Palette.health(c.status))
                        if let ms = c.ms {
                            Text(String(format: "%.0f ms", ms))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var liveLabel: String {
        if let t = store.tunnels.first(where: { $0.id == check.id }) { return t.up ? "Up" : "Down" }
        if let d = store.deploys.first(where: { $0.id == check.id }) { return d.health }
        return "—"
    }

    private var liveColor: Color {
        if let t = store.tunnels.first(where: { $0.id == check.id }) { return t.up ? .green : .red }
        if let d = store.deploys.first(where: { $0.id == check.id }) { return Palette.health(d.health) }
        return .secondary
    }

    private func kv(_ k: String, _ v: String) -> some View {
        LabeledContent(k) {
            Text(v)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    @ViewBuilder private func cmd(_ k: String, _ parts: [String]?) -> some View {
        if let parts, !parts.isEmpty {
            kv(k, parts.joined(separator: " "))
        }
    }
}

struct Panel: View {
    @ObservedObject var store: Store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Tunnels") {
                        Text("\(store.tunnelsUp) of \(store.tunnels.count)")
                            .monospacedDigit()
                    }
                    LabeledContent("Healthy") {
                        Text("\(store.healthyDeploys) of \(store.deploys.count)")
                            .monospacedDigit()
                    }
                    if store.degradedDeploys > 0 {
                        LabeledContent("Degraded") {
                            Text("\(store.degradedDeploys)").foregroundStyle(.orange).monospacedDigit()
                        }
                    }
                    if store.downDeploys > 0 {
                        LabeledContent("Down") {
                            Text("\(store.downDeploys)").foregroundStyle(.red).monospacedDigit()
                        }
                    }
                    if store.driftDeploys > 0 {
                        LabeledContent("Version drift") {
                            Text("\(store.driftDeploys)").monospacedDigit()
                        }
                    }
                    if store.fleetSpark.count > 1 {
                        HStack {
                            Text("Fleet")
                            Spark(values: store.fleetSpark, wide: true)
                        }
                        .help("Average health across apps")
                    }
                } header: {
                    Text("Overview")
                }

                Section("Tunnels") {
                    ForEach(store.tunnels) { row in
                        TunnelCard(row: row)
                    }
                }

                ForEach(regionGroups(store.deploys)) { group in
                    Section(group.key) {
                        ForEach(group.items) { d in
                            DeployCard(d: d)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .toolbar {
                ToolbarItem(placement: .status) {
                    Text(store.lastCheckedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Time of the last poll")
                }
                ToolbarItem {
                    Button {
                        store.load()
                        store.poll()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .help("Reload")
                }
                ToolbarItem {
                    Button {
                        store.openConfigWindow()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings")
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}

struct TunnelCard: View {
    var row: TunnelRow
    @ObservedObject var store = Store.shared

    var body: some View {
        DisclosureGroup(isExpanded: store.expandBinding(row.id)) {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Listen") {
                    Text(row.port.map { "\(row.host):\($0)" } ?? row.host)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("State") {
                    Text(row.up ? "Listening" : "Not listening")
                }
                if let proc = row.process {
                    LabeledContent("Process") { Text(proc) }
                }
                if let pid = row.pid {
                    LabeledContent("PID") { Text(pid).monospacedDigit() }
                }
                if let e = row.elapsed {
                    LabeledContent("Up") { Text(e) }
                }
                if let cmd = row.command {
                    Text(cmd)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    if row.up {
                        if row.canStop {
                            Button("Disconnect") { store.runTunnel(row.id, kind: .stop) }
                        }
                        if row.canOpen {
                            Button("Open") { store.runTunnel(row.id, kind: .open) }
                        }
                    } else if row.canStart {
                        Button("Connect") { store.runTunnel(row.id, kind: .start) }
                    }
                }
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        } label: {
            Label {
                HStack {
                    Text(row.title)
                    Spacer()
                    if let port = row.port {
                        Text("\(row.host):\(port)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Mark(
                        ok: row.up && !row.busy,
                        label: row.up ? "Tunnel is listening" : "Nothing is listening on this port"
                    )
                }
            } icon: {
                BrandIcon(title: row.title)
            }
        }
    }
}

struct DeployCard: View {
    var d: DeployRow
    @ObservedObject var store = Store.shared

    var body: some View {
        DisclosureGroup(isExpanded: store.expandBinding(d.id)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    LabeledContent("Health") { Text(d.health) }
                    LabeledContent("Checks") {
                        Text("\(d.okCount)/\(d.checks.count)").monospacedDigit()
                    }
                    LabeledContent("Avg") {
                        Text(d.avgMs.map { String(format: "%.0f ms", $0) } ?? "—")
                            .monospacedDigit()
                    }
                    if let u = d.uptime {
                        LabeledContent("Uptime") {
                            Text(String(format: "%.1fs", u)).monospacedDigit()
                        }
                    }
                }
                .font(.caption)
                if d.spark.count > 1 {
                    Spark(values: d.spark, wide: true)
                }
                if d.checks.contains(where: { $0.ms != nil }) {
                    LatencyChart(checks: d.checks)
                }
                VersionBar(app: d.liveVersion, deploy: d.k8sVersion, live: d.k8sLiveVersion)
                LabeledContent("App live") { Text(d.liveVersion).font(.caption.monospaced()) }
                LabeledContent("k8s deploy") { Text(d.k8sVersion).font(.caption.monospaced()) }
                LabeledContent("k8s live") { Text(d.k8sLiveVersion).font(.caption.monospaced()) }
                ForEach(d.checks) { c in
                    LabeledContent(c.name) {
                        Text(c.ms.map { "\(c.status) · \(String(format: "%.0f ms", $0))" } ?? c.status)
                            .foregroundStyle(Palette.health(c.status))
                    }
                }
                if let url = d.openUrl {
                    Button("Open health") { store.openURL(url) }
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text(envLabel(d.title))
                Spacer()
                if !store.expanded.contains(d.id) {
                    CheckDots(checks: d.checks)
                    Spark(values: d.spark)
                }
                Mark(ok: d.up, warn: d.health == "degraded", label: "Overall health: \(d.health)")
            }
        }
    }
}
