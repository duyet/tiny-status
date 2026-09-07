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
    var accent: Color = .clear
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.10))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 12, bottomLeadingRadius: 12,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                )
                .fill(accent)
                .frame(width: 4)
            }
    }
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
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background((ok ? Color.green : tint).opacity(0.18), in: Capsule())
        .foregroundStyle(ok ? Color.green : tint)
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
                TextField("Seconds", value: $store.editPollSeconds, format: .number)
            } header: {
                Label("Check", systemImage: "timer")
            }
            Section {
                Toggle(isOn: $store.editAlertsEnabled) { Label("Enabled", systemImage: "bell") }
                Toggle(isOn: $store.editOnDown) { Label("On down", systemImage: "xmark.octagon") }
                Toggle(isOn: $store.editOnRecover) { Label("On recover", systemImage: "checkmark.seal") }
                Toggle(isOn: $store.editOnDrift) { Label("On version drift", systemImage: "arrow.left.arrow.right") }
                TextField("Seconds", value: $store.editCooldown, format: .number)
            } header: {
                Label("Alerts", systemImage: "bell.badge")
            }
            Section {
                LabeledContent {
                    Text(ConfigLoader.userURL.path)
                        .font(.caption)
                        .textSelection(.enabled)
                } label: {
                    Label("Path", systemImage: "doc")
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
                    .frame(minHeight: 160)
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
        .frame(minWidth: 520, minHeight: 480)
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

struct Overview: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Overview", systemImage: "square.grid.2x2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.lastCheckedLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                MetricChip(
                    icon: "network",
                    title: "Tunnels",
                    value: "\(store.tunnelsUp)/\(store.tunnels.count)",
                    color: store.tunnelsUp == store.tunnels.count && !store.tunnels.isEmpty ? .green : Palette.gitlab
                )
                MetricChip(
                    icon: "checkmark.seal.fill",
                    title: "Healthy",
                    value: "\(store.healthyDeploys)/\(store.deploys.count)",
                    color: .green
                )
                MetricChip(
                    icon: "exclamationmark.triangle.fill",
                    title: "Degraded",
                    value: "\(store.degradedDeploys)",
                    color: store.degradedDeploys == 0 ? .green : .orange
                )
                MetricChip(
                    icon: "xmark.octagon.fill",
                    title: "Down",
                    value: "\(store.downDeploys)",
                    color: store.downDeploys == 0 ? .green : .red
                )
                MetricChip(
                    icon: "arrow.left.arrow.right",
                    title: "Drift",
                    value: "\(store.driftDeploys)",
                    color: store.driftDeploys == 0 ? .green : Palette.deploy
                )
            }
            HStack(spacing: 8) {
                ForEach(regionGroups(store.deploys)) { g in
                    let ok = g.items.filter { $0.health == "healthy" }.count
                    HStack(spacing: 4) {
                        Circle().fill(Palette.region(g.key)).frame(width: 7, height: 7)
                        Text(g.key).font(.caption2.weight(.semibold))
                        Text("\(ok)/\(g.items.count)")
                            .font(.caption2.monospaced())
                    }
                    .foregroundStyle(Palette.region(g.key))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Palette.region(g.key).opacity(0.12), in: Capsule())
                    .help("\(g.key): \(ok) of \(g.items.count) healthy")
                }
                Spark(values: store.fleetSpark, wide: true)
                    .help("Average health across all apps")
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct Panel: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Overview(store: store)
                    ForEach(store.tunnels) { row in
                        TunnelCard(row: row)
                    }
                    ForEach(regionGroups(store.deploys)) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle().fill(Palette.region(group.key)).frame(width: 8, height: 8)
                                    .help("\(group.key) region")
                                Label(group.key, systemImage: regionIcon(group.key))
                                    .font(.caption.weight(.semibold))
                                    .help("\(group.key): deployments in this region")
                            }
                            .foregroundStyle(Palette.region(group.key))
                            .padding(.top, 4)
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                                spacing: 8
                            ) {
                                ForEach(group.items) { d in
                                    DeployCard(d: d)
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                    .help("Time of the last poll")
                Text(store.lastCheckedLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Mark(ok: store.allOK)
                IconBtn(system: "gearshape", help: "Settings") { store.openConfigWindow() }
                IconBtn(system: "arrow.clockwise", help: "Reload") { store.load(); store.poll() }
                IconBtn(system: "xmark.circle", help: "Quit") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 560, minHeight: 480)
    }
}

struct TunnelCard: View {
    var row: TunnelRow
    @ObservedObject var store = Store.shared
    var open: Bool { store.expanded.contains(row.id) }
    var body: some View {
        Card(accent: Palette.gitlab) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button { store.toggleExpand(row.id) } label: {
                        HStack(spacing: 8) {
                            BrandIcon(title: row.title)
                            Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.gitlab)
                            Text(row.port.map { "\(row.host):\($0)" } ?? "")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(open ? 90 : 0))
                                .help(open ? "Collapse details" : "Expand: port, pid, uptime, ssh command")
                            Spacer(minLength: 4)
                            Mark(
                                ok: row.up && !row.busy,
                                label: row.up ? "Tunnel is listening" : "Nothing is listening on this port"
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if row.up {
                        if row.canStop {
                            IconBtn(system: "pause.circle", help: "Disconnect") {
                                store.runTunnel(row.id, kind: .stop)
                            }
                        }
                        if row.canOpen {
                            IconBtn(system: "safari", help: "Open") {
                                store.runTunnel(row.id, kind: .open)
                            }
                        }
                    } else if row.canStart {
                        IconBtn(system: "link", help: "Connect") {
                            store.runTunnel(row.id, kind: .start)
                        }
                    }
                }
                if open {
                    HStack(spacing: 6) {
                        Image(systemName: "network").foregroundStyle(.secondary).imageScale(.small)
                            .help("Local listen address")
                        Text(row.port.map { "\(row.host):\($0)" } ?? row.host)
                            .font(.caption.monospaced())
                        if row.up {
                            Text("listening").font(.caption2).foregroundStyle(.green)
                        } else {
                            Text("nothing listening").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if row.up {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal").foregroundStyle(.secondary).imageScale(.small)
                                .help("Process holding the port (often ssh)")
                            Text(row.process ?? "process")
                            if let pid = row.pid { Text("pid \(pid)").foregroundStyle(.secondary) }
                            if let e = row.elapsed { Text("up \(e)").foregroundStyle(.secondary) }
                        }
                        .font(.caption2)
                        if let cmd = row.command {
                            Text(cmd)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("Start a local forward to this port, or tap Connect if a start command is configured.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct DeployCard: View {
    var d: DeployRow
    @ObservedObject var store = Store.shared
    var open: Bool { store.expanded.contains(d.id) }
    var body: some View {
        Card(accent: Palette.region(d.title)) {
            VStack(alignment: .leading, spacing: 6) {
                Button { store.toggleExpand(d.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: d.title.lowercased().contains("prod") ? "server.rack" : "hammer")
                            .foregroundStyle(Palette.region(d.title))
                            .frame(width: 14)
                            .help(d.title.lowercased().contains("prod") ? "Production" : "Development")
                        Text(envLabel(d.title))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.region(d.title))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .help(open ? "Collapse details" : "Expand: health, versions, checks")
                        Spacer(minLength: 2)
                        if !open { Spark(values: d.spark) }
                        Mark(
                            ok: d.up,
                            warn: d.health == "degraded",
                            label: "Overall health: \(d.health)"
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !open {
                    CheckDots(checks: d.checks)
                }
                if open {
                    HStack(spacing: 6) {
                        MetricChip(
                            icon: "heart.fill",
                            title: "Health",
                            value: d.health,
                            color: Palette.health(d.health)
                        )
                        MetricChip(
                            icon: "checkmark.circle",
                            title: "Checks",
                            value: "\(d.okCount)/\(max(d.checks.count, 0))",
                            color: d.okCount == d.checks.count && !d.checks.isEmpty ? .green : .orange
                        )
                        MetricChip(
                            icon: "speedometer",
                            title: "Avg latency",
                            value: d.avgMs.map { String(format: "%.0f ms", $0) } ?? "—",
                            color: Palette.app
                        )
                        MetricChip(
                            icon: "clock",
                            title: "Uptime",
                            value: d.uptime.map { String(format: "%.1fs", $0) } ?? "—",
                            color: Palette.pod
                        )
                    }
                    if d.spark.count > 1 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health history")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spark(values: d.spark, wide: true)
                        }
                    }
                    if d.checks.contains(where: { $0.ms != nil }) {
                        LatencyChart(checks: d.checks)
                    }
                    VersionBar(app: d.liveVersion, deploy: d.k8sVersion, live: d.k8sLiveVersion)
                    Line(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "App live",
                        value: d.liveVersion,
                        ok: d.up
                    )
                    Line(
                        icon: "shippingbox",
                        label: "k8s deploy",
                        value: d.k8sVersion,
                        ok: d.k8sVersion != "—" && d.k8sVersion == d.k8sLiveVersion
                    )
                    Line(
                        icon: "memorychip",
                        label: "k8s live",
                        value: d.k8sLiveVersion,
                        ok: d.k8sLiveVersion != "—" && d.k8sLiveVersion == d.liveVersion
                    )
                    if !d.checks.isEmpty {
                        ForEach(d.checks) { c in
                            Line(
                                icon: checkIcon(c.name),
                                label: c.name,
                                value: c.ms.map { "\(c.status)  \(String(format: "%.0f ms", $0))" } ?? c.status,
                                ok: c.status == "healthy",
                                warn: c.status == "degraded"
                            )
                        }
                    }
                    if let url = d.openUrl {
                        Button { store.openURL(url) } label: {
                            Label("Open health", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}
