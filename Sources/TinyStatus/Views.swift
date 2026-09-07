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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.background.secondary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.45), lineWidth: 1)
            }
    }
}

struct Mark: View {
    var ok: Bool
    var warn: Bool = false
    var body: some View {
        Image(systemName: warn ? "exclamationmark.circle.fill" : ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(warn ? Color.orange : ok ? Color.green : Color.red)
            .imageScale(.medium)
            .symbolRenderingMode(.hierarchical)
    }
}

struct Line: View {
    var icon: String
    var label: String
    var value: String
    var ok: Bool
    var warn: Bool = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Mark(ok: ok, warn: warn)
        }
        .font(.callout)
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
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        .frame(width: 76, height: 20)
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
        HStack(spacing: 4) {
            ForEach(checks) { c in
                Circle()
                    .fill(c.status == "healthy" ? Color.green : c.status == "degraded" ? Color.orange : Color.red)
                    .frame(width: 7, height: 7)
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
        HStack(spacing: 6) {
            pill("app", app, deploy == app && live == app)
            pill("deploy", deploy, deploy == live)
            pill("pod", live, live == app)
        }
    }

    private func pill(_ name: String, _ value: String, _ ok: Bool) -> some View {
        Text("\(name) \(value)")
            .font(.caption2.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(ok ? Color.green.opacity(0.18) : Color.red.opacity(0.18), in: Capsule())
            .foregroundStyle(ok ? Color.green : Color.red)
    }
}

func regionIcon(_ title: String) -> String {
    let t = title.lowercased()
    if t.contains("gitlab") { return "network" }
    if t.hasPrefix("sg") { return "globe.asia.australia.fill" }
    if t.hasPrefix("eu") { return "globe.europe.africa.fill" }
    if t.hasPrefix("za") { return "globe" }
    return "server.rack"
}

struct ConfigWindow: View {
    @ObservedObject var store: Store

    var body: some View {
        Form {
            Section("Check") {
                TextField("Interval (seconds)", value: $store.editPollSeconds, format: .number)
            }
            Section("Alerts") {
                Toggle("Enabled", isOn: $store.editAlertsEnabled)
                Toggle("On down", isOn: $store.editOnDown)
                Toggle("On recover", isOn: $store.editOnRecover)
                Toggle("On version drift", isOn: $store.editOnDrift)
                TextField("Cooldown (seconds)", value: $store.editCooldown, format: .number)
            }
            Section("File") {
                Text(ConfigLoader.userURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigLoader.userURL])
                }
            }
            Section("Git backup") {
                Toggle("Enabled", isOn: $store.editBackupEnabled)
                Toggle("Backup on Save", isOn: $store.editBackupAuto)
                TextField("Repo folder", text: $store.editBackupRepo)
                TextField("File in repo", text: $store.editBackupFile)
                TextField("Remote", text: $store.editBackupRemote)
                TextField("Branch", text: $store.editBackupBranch)
                TextField("Clone URL (optional)", text: $store.editBackupRemoteUrl)
                HStack {
                    Button("Backup") { store.gitBackup() }
                    Button("Pull") { store.gitPull() }
                    Button("Sync") { store.gitSync() }
                }
                .buttonStyle(.bordered)
                .disabled(store.gitBusy || !store.editBackupEnabled)
                if store.gitConflict {
                    HStack {
                        Button("Keep local") { store.gitKeepLocal() }
                        Button("Keep remote") { store.gitKeepRemote() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if !store.gitLog.isEmpty {
                    Text(store.gitLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Section("JSON") {
                TextEditor(text: $store.configText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
            }
            if let error = store.configError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 560)
        .onAppear { store.loadConfigEditor() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { store.saveConfig() }
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
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.tunnels) { row in
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label(row.title, systemImage: "network")
                                        .font(.headline)
                                        .labelStyle(.titleAndIcon)
                                    Spacer()
                                    Mark(ok: row.up && !row.busy)
                                }
                                Line(
                                    icon: "bolt.horizontal.circle",
                                    label: "Status",
                                    value: row.busy ? "…" : row.up ? "Connected" : "Disconnected",
                                    ok: row.up && !row.busy
                                )
                                HStack(spacing: 8) {
                                    Button { store.runTunnel(row.id, kind: .start) } label: {
                                        Label("Connect", systemImage: "link")
                                    }
                                    Button { store.runTunnel(row.id, kind: .stop) } label: {
                                        Label("Disconnect", systemImage: "pause.circle")
                                    }
                                    Button { store.runTunnel(row.id, kind: .open) } label: {
                                        Label("Open", systemImage: "safari")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                    ForEach(store.deploys) { d in
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center, spacing: 8) {
                                    Label(d.title, systemImage: regionIcon(d.title))
                                        .font(.headline)
                                    Spacer()
                                    Spark(values: d.spark)
                                    Mark(ok: d.up, warn: d.health == "degraded")
                                }
                                Line(
                                    icon: "heart",
                                    label: "Health",
                                    value: d.health,
                                    ok: d.up,
                                    warn: d.health == "degraded"
                                )
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
                                    HStack {
                                        Image(systemName: "circle.grid.2x1")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 14)
                                        Text("Checks")
                                        Spacer()
                                        CheckDots(checks: d.checks)
                                    }
                                    .font(.callout)
                                    DisclosureGroup("Details") {
                                        ForEach(d.checks) { c in
                                            Line(
                                                icon: "stethoscope",
                                                label: c.name,
                                                value: c.status,
                                                ok: c.status == "healthy",
                                                warn: c.status == "degraded"
                                            )
                                        }
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
                .padding(16)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(store.lastCheckedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Mark(ok: store.allOK)
                }
                HStack(spacing: 8) {
                    Button { store.openConfigWindow() } label: {
                        Label("Config", systemImage: "gearshape")
                    }
                    Button { store.load(); store.poll() } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Button { NSApp.terminate(nil) } label: {
                        Label("Quit", systemImage: "xmark.circle")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(.bar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 380, minHeight: 520)
    }
}

