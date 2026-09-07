import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var tunnels: [TunnelRow] = []
    @Published var deploys: [DeployRow] = []
    @Published var configText = ""
    @Published var configError: String?
    @Published var lastChecked: Date?
    @Published var editPollSeconds: Double = 30
    @Published var editAlertsEnabled = true
    @Published var editOnDown = true
    @Published var editOnRecover = true
    @Published var editOnDrift = true
    @Published var editCooldown: Double = 300
    @Published var editBackupEnabled = true
    @Published var editBackupAuto = false
    @Published var editBackupRepo = ""
    @Published var editBackupFile = "backup/tunnels.json"
    @Published var editBackupRemote = "origin"
    @Published var editBackupBranch = "master"
    @Published var editBackupRemoteUrl = ""
    @Published var gitLog = ""
    @Published var gitBusy = false
    @Published var gitConflict = false
    @Published var expanded: Set<String> = []

    func toggleExpand(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    func expandBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.expanded.contains(id) },
            set: { on in
                if on { self.expanded.insert(id) } else { self.expanded.remove(id) }
            }
        )
    }

    var lastCheckedLabel: String {
        guard let d = lastChecked else { return "Not checked yet" }
        let abs = d.formatted(date: .omitted, time: .standard)
        let rel = d.formatted(.relative(presentation: .named, unitsStyle: .narrow))
        return "Checked \(abs) · \(rel)"
    }

    var allOK: Bool {
        !tunnels.isEmpty && tunnels.allSatisfy(\.up) && deploys.allSatisfy(\.up)
    }

    var barSymbol: String {
        if tunnels.contains(where: \.busy) || deploys.contains(where: { $0.health == "…" }) {
            return "ellipsis.circle.fill"
        }
        return allOK ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var barColor: Color { allOK ? .green : .red }

    var tunnelsUp: Int { tunnels.filter(\.up).count }
    var healthyDeploys: Int { deploys.filter { $0.health == "healthy" }.count }
    var degradedDeploys: Int { deploys.filter { $0.health == "degraded" }.count }
    var downDeploys: Int { deploys.filter { $0.health != "healthy" && $0.health != "degraded" && $0.health != "…" }.count }
    var driftDeploys: Int {
        deploys.filter {
            $0.k8sVersion != "—" && $0.k8sLiveVersion != "—"
                && ($0.k8sVersion != $0.k8sLiveVersion || ($0.liveVersion != "—" && $0.liveVersion != $0.k8sLiveVersion))
        }.count
    }
    var fleetSpark: [Double] {
        let n = deploys.map(\.spark.count).max() ?? 0
        guard n > 1 else { return deploys.map { DeployRow.healthScore($0.health) } }
        return (0..<n).map { i in
            let xs = deploys.compactMap { $0.spark.indices.contains(i) ? $0.spark[i] : nil }
            guard !xs.isEmpty else { return 0 }
            return xs.reduce(0, +) / Double(xs.count)
        }
    }
    private var cfg = Config()
    private var busy = Set<String>()
    private var timer: Timer?
    private var cfgStamp: Date?
    private var lastAlert: [String: Date] = [:]

    init() {
        Notify.request()
        load()
        poll()
    }

    func tick() {
        reloadIfChanged()
        poll()
    }

    func allChecks() -> [Check] {
        var seen = Set<String>()
        var out: [Check] = []
        for c in (cfg.checks ?? [])
            + (cfg.tunnels ?? []).map(Check.from(tunnel:))
            + (cfg.deployments ?? []).map(Check.from(deployment:))
        {
            if seen.insert(c.id).inserted { out.append(c) }
        }
        return out
    }

    func load() {
        cfg = ConfigLoader.load()
        cfgStamp = ConfigLoader.mtime()
        let checks = allChecks()
        tunnels = checks.filter { $0.kind == .tcp }.map {
            TunnelRow(id: $0.id, title: $0.title, up: false, busy: false, host: $0.host ?? "127.0.0.1", port: $0.port)
        }
        deploys = checks.filter { $0.kind != .tcp }.map {
            DeployRow(
                id: $0.id, title: $0.title, health: "…", liveVersion: "…",
                k8sVersion: "…", k8sLiveVersion: "…", checks: [], openUrl: $0.openUrl ?? $0.url
            )
        }
        applyCache()
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        let n = cfg.pollSeconds ?? 30
        timer = Timer.scheduledTimer(withTimeInterval: n, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func applyCache() {
        guard let snap = DiskCache.load() else { return }
        lastAlert = snap.lastAlert
        lastChecked = snap.lastChecked
        tunnels = tunnels.map { r in
            var r = r
            if let up = snap.tunnels[r.id] { r.up = up }
            return r
        }
        deploys = deploys.map { r in
            guard let c = snap.deploys[r.id] else { return r }
            var r = r
            r.health = c.health
            r.liveVersion = c.liveVersion
            r.k8sVersion = c.k8sVersion
            r.k8sLiveVersion = c.k8sLiveVersion
            r.spark = c.spark ?? []
            return r
        }
    }

    private func reloadIfChanged() {
        if ConfigLoader.mtime() != cfgStamp { load() }
    }

    func poll() {
        let checks = allChecks()
        let busyNow = busy
        Task.detached {
            var infos: [String: TunnelInfo] = [:]
            var drows: [String: DeployRow] = [:]
            await withTaskGroup(of: (String, TunnelInfo?, DeployRow?).self) { g in
                for c in checks where !busyNow.contains(c.id) {
                    g.addTask {
                        let r = Probe.check(c)
                        return (c.id, r.tunnel, r.deploy)
                    }
                }
                for await x in g {
                    if let t = x.1 { infos[x.0] = t }
                    if let d = x.2 { drows[x.0] = d }
                }
            }
            await MainActor.run { self.apply(tunnels: infos, deploys: drows) }
        }
    }

    private func apply(tunnels infos: [String: TunnelInfo], deploys: [String: DeployRow]) {
        let prevT = Dictionary(uniqueKeysWithValues: self.tunnels.map { ($0.id, $0) })
        let tcp = allChecks().filter { $0.kind == .tcp }
        let httpish = allChecks().filter { $0.kind != .tcp }
        tunnels = tcp.map { t in
            let old = self.tunnels.first { $0.id == t.id }
            let info = infos[t.id]
            var spark = old?.spark ?? []
            let up = info?.up ?? old?.up ?? false
            if info != nil {
                spark.append(up ? 1 : 0)
                if spark.count > 40 { spark = Array(spark.suffix(40)) }
            }
            return TunnelRow(
                id: t.id,
                title: t.title,
                up: up,
                busy: busy.contains(t.id),
                host: info?.host ?? t.host ?? "127.0.0.1",
                port: info?.port ?? t.port,
                pid: info == nil ? old?.pid : info?.pid,
                process: info == nil ? old?.process : info?.process,
                elapsed: info == nil ? old?.elapsed : info?.elapsed,
                command: info == nil ? old?.command : info?.command,
                canStart: t.start != nil,
                canStop: t.stop != nil,
                canOpen: t.open != nil,
                spark: spark,
                ms: info == nil ? old?.ms : info?.ms
            )
        }
        let prevD = Dictionary(uniqueKeysWithValues: self.deploys.map { ($0.id, $0) })
        self.deploys = httpish.map { d in
            var row = deploys[d.id] ?? self.deploys.first { $0.id == d.id }
                ?? DeployRow(
                    id: d.id, title: d.title, health: "…", liveVersion: "…",
                    k8sVersion: "…", k8sLiveVersion: "…", checks: [], openUrl: d.openUrl ?? d.url
                )
            if row.health != "…" {
                var s = prevD[d.id]?.spark ?? row.spark
                s.append(DeployRow.healthScore(row.health))
                if s.count > 40 { s = Array(s.suffix(40)) }
                row.spark = s
                let prevC = Dictionary(uniqueKeysWithValues: (prevD[d.id]?.checks ?? []).map { ($0.name, $0) })
                row.checks = row.checks.map { c in
                    var c = c
                    var cs = prevC[c.name]?.spark ?? []
                    cs.append(DeployRow.healthScore(c.status))
                    if cs.count > 40 { cs = Array(cs.suffix(40)) }
                    c.spark = cs
                    return c
                }
            }
            return row
        }
        lastChecked = Date()
        alertDiffs(prevT: prevT, prevD: prevD)
        DiskCache.save(
            CacheFile(
                tunnels: Dictionary(uniqueKeysWithValues: tunnels.map { ($0.id, $0.up) }),
                deploys: Dictionary(uniqueKeysWithValues: self.deploys.map {
                    ($0.id, CachedDeploy(
                        health: $0.health, liveVersion: $0.liveVersion,
                        k8sVersion: $0.k8sVersion, k8sLiveVersion: $0.k8sLiveVersion,
                        spark: $0.spark
                    ))
                }),
                lastAlert: lastAlert,
                lastChecked: lastChecked
            )
        )
    }

    private func alertDiffs(prevT: [String: TunnelRow], prevD: [String: DeployRow]) {
        let a = cfg.alerts
        guard a?.enabled ?? true else { return }
        let onDown = a?.onDown ?? true
        let onRecover = a?.onRecover ?? true
        let onDrift = a?.onVersionDrift ?? true
        let cool = a?.cooldownSeconds ?? 300
        for t in tunnels {
            let old = prevT[t.id]
            guard let old, !old.busy, t.up != old.up else { continue }
            if !t.up, onDown { ping(t.id, t.title, "Disconnected", cool) }
            if t.up, onRecover { ping(t.id, t.title, "Connected", cool) }
        }
        for d in deploys {
            let old = prevD[d.id]
            let oldH = old?.health ?? "…"
            if d.health == "…" { continue }
            if onDown, oldH == "healthy", !d.up {
                ping(d.id, d.title, "Health \(d.health)", cool)
            }
            if onRecover, oldH != "healthy", oldH != "…", d.up {
                ping(d.id, d.title, "Healthy again", cool)
            }
            if onDrift {
                let drift = d.k8sVersion != "—" && d.k8sLiveVersion != "—"
                    && (d.k8sVersion != d.k8sLiveVersion || (d.liveVersion != "—" && d.liveVersion != d.k8sLiveVersion))
                let wasDrift = old.map {
                    $0.k8sVersion != "—" && $0.k8sLiveVersion != "—"
                        && ($0.k8sVersion != $0.k8sLiveVersion
                            || ($0.liveVersion != "—" && $0.liveVersion != $0.k8sLiveVersion))
                } ?? false
                if drift, !wasDrift {
                    ping(
                        d.id + ".drift",
                        d.title,
                        "Version drift  k8s \(d.k8sVersion)  live \(d.k8sLiveVersion)  app \(d.liveVersion)",
                        cool
                    )
                }
            }
        }
    }

    private func ping(_ id: String, _ title: String, _ body: String, _ cool: Double) {
        if let last = lastAlert[id], Date().timeIntervalSince(last) < cool { return }
        lastAlert[id] = Date()
        Notify.post(id: id, title: title, body: body)
    }

    func runTunnel(_ id: String, kind: TunnelAction) {
        guard let t = (cfg.tunnels ?? []).first(where: { $0.id == id }) else { return }
        let cmd: [String]? = switch kind {
        case .start: t.start
        case .stop: t.stop
        case .open: t.open
        }
        guard let cmd else { return }
        busy.insert(id)
        tunnels = tunnels.map { r in
            var r = r
            if r.id == id { r.busy = true }
            return r
        }
        Task.detached {
            _ = Shell.run(cmd, timeout: 90)
            await MainActor.run {
                self.busy.remove(id)
                self.poll()
            }
        }
    }

    func openURL(_ s: String) {
        guard let u = URL(string: s) else { return }
        NSWorkspace.shared.open(u)
    }

    func loadConfigEditor() {
        configText = (try? String(contentsOf: ConfigLoader.userURL, encoding: .utf8)) ?? ""
        configError = nil
        let c = cfg
        editPollSeconds = c.pollSeconds ?? 30
        editAlertsEnabled = c.alerts?.enabled ?? true
        editOnDown = c.alerts?.onDown ?? true
        editOnRecover = c.alerts?.onRecover ?? true
        editOnDrift = c.alerts?.onVersionDrift ?? true
        editCooldown = c.alerts?.cooldownSeconds ?? 300
        editBackupEnabled = c.backup?.enabled ?? true
        editBackupAuto = c.backup?.autoOnSave ?? false
        editBackupRepo = c.backup?.repo ?? "{home}/.config/tiny-status/git-backup"
        editBackupFile = c.backup?.file ?? "backup/tunnels.json"
        editBackupRemote = c.backup?.remote ?? "origin"
        editBackupBranch = c.backup?.branch ?? "master"
        editBackupRemoteUrl = c.backup?.remoteUrl ?? ""
    }

    func openConfigWindow() {
        loadConfigEditor()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func openStandaloneWindow() {
        AppDelegate.instance?.showMain()
    }

    func saveConfig() {
        do {
            var root: [String: Any] = [:]
            if let data = configText.data(using: .utf8),
               let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                root = obj
            }
            root["pollSeconds"] = editPollSeconds
            root["alerts"] = [
                "enabled": editAlertsEnabled,
                "onDown": editOnDown,
                "onRecover": editOnRecover,
                "onVersionDrift": editOnDrift,
                "cooldownSeconds": editCooldown,
            ]
            root["backup"] = [
                "enabled": editBackupEnabled,
                "autoOnSave": editBackupAuto,
                "repo": editBackupRepo,
                "file": editBackupFile,
                "remote": editBackupRemote,
                "branch": editBackupBranch,
                "remoteUrl": editBackupRemoteUrl,
            ]
            let out = try JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
            )
            _ = try JSONDecoder().decode(Config.self, from: out)
            try out.write(to: ConfigLoader.userURL, options: .atomic)
            configText = String(data: out, encoding: .utf8) ?? configText
            configError = nil
            load()
            poll()
            if editBackupEnabled, editBackupAuto { gitBackup() }
        } catch {
            configError = error.localizedDescription
        }
    }

    func gitBackup() { gitGo(.backup) }
    func gitPull() { gitGo(.pull) }
    func gitSync() { gitGo(.sync) }
    func gitKeepLocal() { gitGo(.keepLocal) }
    func gitKeepRemote() { gitGo(.keepRemote) }

    private func gitGo(_ op: GitBackup.Op) {
        gitBusy = true
        gitLog = "Working…"
        let spec = GitBackup.Spec(
            repo: ConfigLoader.expand(editBackupRepo),
            file: editBackupFile,
            remote: editBackupRemote,
            branch: editBackupBranch,
            remoteUrl: editBackupRemoteUrl.isEmpty ? nil : editBackupRemoteUrl,
            localConfig: ConfigLoader.userURL
        )
        Task.detached {
            let (ok, log, conflict) = GitBackup.run(op, spec)
            await MainActor.run {
                self.gitBusy = false
                self.gitLog = log
                self.gitConflict = conflict
                if ok, op == .pull || op == .keepRemote {
                    self.load()
                    self.loadConfigEditor()
                    self.poll()
                }
            }
        }
    }

    func importPaste(_ text: String) {
        let parsed = Discovery.parse(text)
        Task.detached {
            var added: [Check] = []
            for p in parsed {
                if p.kind == .http, p.discover, let u = p.url, let url = URL(string: u),
                   let found = Discovery.probeHTTP(base: url)
                {
                    added.append(found.asCheck())
                } else {
                    added.append(p.asCheck())
                }
            }
            await MainActor.run { self.appendChecks(added) }
        }
    }

    func appendChecks(_ new: [Check]) {
        guard !new.isEmpty else { return }
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: ConfigLoader.userURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            root = obj
        }
        var list = cfg.checks ?? []
        var seen = Set(list.map(\.id))
        list.append(contentsOf: new.filter { seen.insert($0.id).inserted })
        cfg.checks = list
        if let encoded = try? JSONEncoder().encode(list),
           let arr = try? JSONSerialization.jsonObject(with: encoded)
        {
            root["checks"] = arr
        }
        if let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: ConfigLoader.userURL, options: .atomic)
        }
        load()
        poll()
    }

    enum TunnelAction { case start, stop, open }
}
