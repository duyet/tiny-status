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

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background.secondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
            }
    }
}

struct Mark: View {
    var ok: Bool
    var warn: Bool = false
    var body: some View {
        Image(systemName: warn ? "exclamationmark.circle.fill" : ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(warn ? Color.orange : ok ? Color.green : Color.red)
            .imageScale(.small)
            .symbolRenderingMode(.hierarchical)
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
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .imageScale(.small)
            Text(label)
            Spacer(minLength: 6)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Mark(ok: ok, warn: warn)
        }
        .font(.caption)
    }
}

struct Spark: View {
    var values: [Double]
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
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
        .frame(width: 56, height: 16)
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
                    .help("\(c.name): \(c.status)")
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
            pill("iphone", app, deploy == app && live == app)
            pill("shippingbox", deploy, deploy == live)
            pill("memorychip", live, live == app)
        }
    }

    private func pill(_ icon: String, _ value: String, _ ok: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).imageScale(.small)
            Text(value).font(.caption2.monospaced())
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(ok ? Color.green.opacity(0.16) : Color.orange.opacity(0.16), in: Capsule())
        .foregroundStyle(ok ? Color.green : Color.orange)
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
    }
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

struct Panel: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.tunnels) { row in
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    BrandIcon(title: row.title)
                                    Text(row.title).font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 4)
                                    Mark(ok: row.up && !row.busy)
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
                                HStack(spacing: 6) {
                                    Image(systemName: "network").foregroundStyle(.secondary).imageScale(.small)
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
                                        Text(row.process ?? "process")
                                        if let pid = row.pid { Text("pid \(pid)").foregroundStyle(.secondary) }
                                        if let e = row.elapsed { Text("up \(e)").foregroundStyle(.secondary) }
                                    }
                                    .font(.caption2)
                                    if let cmd = row.command {
                                        Text(cmd)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
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
                    ForEach(regionGroups(store.deploys)) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(group.key, systemImage: regionIcon(group.key))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
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

struct DeployCard: View {
    var d: DeployRow
    @ObservedObject var store = Store.shared
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: d.title.lowercased().contains("prod") ? "server.rack" : "hammer")
                        .foregroundStyle(.tint)
                        .frame(width: 14)
                    Text(envLabel(d.title))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 2)
                    Spark(values: d.spark)
                    Mark(ok: d.up, warn: d.health == "degraded")
                    if let url = d.openUrl {
                        IconBtn(system: "arrow.up.right.square", help: "Open health") {
                            store.openURL(url)
                        }
                    }
                }
                CheckDots(checks: d.checks)
                VersionBar(app: d.liveVersion, deploy: d.k8sVersion, live: d.k8sLiveVersion)
            }
        }
    }
}
