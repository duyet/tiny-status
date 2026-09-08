import Foundation

enum CLI {
    static func run(_ args: [String]) {
        let cmd = args.first ?? "help"
        let rest = Array(args.dropFirst())
        switch cmd {
        case "help", "-h", "--help": help()
        case "version", "-v", "--version":
            emit(["name": "tiny-status", "version": version()])
        case "path":
            emit(["path": ConfigLoader.userURL.path])
        case "config":
            configDump()
        case "list", "ls":
            list()
        case "get":
            get(rest)
        case "add":
            add(rest)
        case "rm", "remove", "delete":
            rm(rest)
        case "probe", "check":
            probe(rest)
        case "action", "run":
            action(rest)
        case "enable":
            setEnabled(rest, true)
        case "disable":
            setEnabled(rest, false)
        case "toggle":
            toggle(rest)
        default:
            fail("unknown command \(cmd). Try tiny-status help", code: 2)
        }
    }

    static let commands: Set<String> = [
        "help", "-h", "--help", "version", "-v", "--version", "path", "config",
        "list", "ls", "get", "add", "rm", "remove", "delete", "probe", "check",
        "action", "run", "enable", "disable", "toggle", "cli", "--cli",
    ]

    private static func help() {
        let text = """
        tiny-status — control TinyStatus config and live checks

        Same binary as TinyStatus.app. No GUI when a command is passed.
        Config: \(ConfigLoader.userURL.path)
        The app reloads that file on its next poll.

        Commands:
          list                 checks + last cached status (JSON)
          get <id>             one check + cache
          add <json|url|host>  add a check; auto-detects /health and writes it
          add -                read JSON or URLs from stdin
          rm <id>              remove from checks / tunnels / deployments
          probe [id]           run probes now (JSON). Exit 1 if any are down
          action <id> <name>   run a check action (start, stop, open, or custom)
          enable <id>          probe this check
          disable <id>         skip probes; stays in the list
          toggle <id>          flip enabled
          config               print the live config file
          path                 print the config path
          version
          help

        Examples (agents):
          tiny-status list
          tiny-status add https://example.com
          tiny-status add '{"url":"https://example.com","group":"homelab"}'
          tiny-status rm web
          tiny-status action ssh start
          tiny-status disable ssh
          tiny-status enable ssh
        """
        FileHandle.standardError.write(Data(text.utf8))
        FileHandle.standardError.write(Data("\n".utf8))
    }

    private static func version() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    private static func configDump() {
        let url = ConfigLoader.userURL
        guard let data = try? Data(contentsOf: url) else { fail("no config at \(url.path)") }
        FileHandle.standardOutput.write(data)
        if data.last != 10 { FileHandle.standardOutput.write(Data("\n".utf8)) }
    }

    private static func list() {
        let cache = DiskCache.load()
        let rows = checks().map { row($0, cache: cache) }
        emit([
            "path": ConfigLoader.userURL.path,
            "lastChecked": iso(cache?.lastChecked),
            "checks": rows,
        ] as [String: Any])
    }

    private static func get(_ rest: [String]) {
        guard let id = rest.first, !id.isEmpty else { fail("usage: tiny-status get <id>", code: 2) }
        let cache = DiskCache.load()
        guard let c = checks().first(where: { $0.id == id }) else { fail("no check \(id)") }
        emit(row(c, cache: cache))
    }

    private static func add(_ rest: [String]) {
        let raw: String
        if rest.first == "-" || rest.isEmpty {
            raw = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } else {
            raw = rest.joined(separator: " ")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { fail("add expects JSON, a URL, or a host", code: 2) }
        var items: [[String: Any]] = []
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data)
        {
            if let arr = obj as? [[String: Any]] {
                items = arr
            } else if let d = obj as? [String: Any] {
                if let arr = d["checks"] as? [[String: Any]] { items = arr }
                else { items = [d] }
            }
        } else {
            let parsed = Discovery.parse(trimmed)
            let httpHosts = Set(parsed.filter { $0.kind == .http }.compactMap(\.host))
            for p in parsed {
                if p.kind == .tcp, let h = p.host, httpHosts.contains(h) { continue }
                items.append(dict(from: p.asCheck()))
            }
        }
        guard !items.isEmpty else { fail("could not infer a check from input", code: 2) }
        var root = loadRoot()
        var list = checkArrays(root).checks
        var seen = Set(allIds(root))
        var added: [[String: Any]] = []
        let paths = (root["discoverPaths"] as? [String]) ?? ConfigLoader.load().discoverPaths
        for item in items {
            var item = item
            if item["kind"] == nil {
                if item["url"] != nil { item["kind"] = "http" }
                else if item["host"] != nil { item["kind"] = "tcp" }
                else if item["command"] != nil { item["kind"] = "command" }
            }
            var check = decodeCheck(item) ?? Check(
                id: item["id"] as? String ?? "check",
                title: item["title"] as? String ?? (item["id"] as? String ?? "check"),
                kind: CheckKind(rawValue: item["kind"] as? String ?? "http") ?? .http,
                url: item["url"] as? String,
                host: item["host"] as? String,
                port: item["port"] as? Int,
                discover: true
            )
            if check.id.isEmpty || check.id == "check" {
                check.id = HealthDiscover.stableId(host: check.host, url: check.url, title: check.title)
            }
            if check.title.isEmpty { check.title = check.id }
            check = HealthDiscover.configure(check, paths: paths)
            if !seen.insert(check.id).inserted { fail("check \(check.id) already exists") }
            let out = dict(from: check, base: item)
            list.append(out)
            added.append(out)
        }
        root["checks"] = list
        saveRoot(root)
        emit(["ok": true, "added": added, "path": ConfigLoader.userURL.path])
    }

    private static func decodeCheck(_ item: [String: Any]) -> Check? {
        guard let data = try? JSONSerialization.data(withJSONObject: item) else { return nil }
        return try? JSONDecoder().decode(Check.self, from: data)
    }

    private static func dict(from c: Check, base: [String: Any] = [:]) -> [String: Any] {
        var item = base
        item["id"] = c.id
        item["title"] = c.title
        item["kind"] = c.kind.rawValue
        if let u = c.url { item["url"] = u } else { item.removeValue(forKey: "url") }
        if let u = c.openUrl { item["openUrl"] = u }
        if let h = c.host { item["host"] = h }
        if let p = c.port { item["port"] = p }
        if let d = c.discover { item["discover"] = d }
        if let i = c.icon { item["icon"] = i }
        if let g = c.group { item["group"] = g }
        if let t = c.tags { item["tags"] = t }
        return item
    }

    private static func rm(_ rest: [String]) {
        guard let id = rest.first, !id.isEmpty else { fail("usage: tiny-status rm <id>", code: 2) }
        var root = loadRoot()
        let before = allIds(root)
        guard before.contains(id) else { fail("no check \(id)") }
        if var checks = root["checks"] as? [[String: Any]] {
            checks.removeAll { ($0["id"] as? String) == id }
            root["checks"] = checks
        }
        if var tunnels = root["tunnels"] as? [[String: Any]] {
            tunnels.removeAll { ($0["id"] as? String) == id }
            root["tunnels"] = tunnels
        }
        if var deployments = root["deployments"] as? [[String: Any]] {
            deployments.removeAll { ($0["id"] as? String) == id }
            root["deployments"] = deployments
        }
        saveRoot(root)
        emit(["ok": true, "removed": id, "path": ConfigLoader.userURL.path])
    }

    private static func probe(_ rest: [String]) {
        var list = checks()
        if let id = rest.first, !id.isEmpty {
            list = list.filter { $0.id == id }
            if list.isEmpty { fail("no check \(id)") }
        } else {
            list = list.filter(\.isEnabled)
        }
        var rows: [[String: Any]] = []
        var down = false
        let paths = ConfigLoader.load().discoverPaths
        for c in list {
            let r = Probe.check(c, discoverPaths: paths)
            var o: [String: Any] = ["id": c.id, "title": c.title, "kind": c.kind.rawValue]
            if let t = r.tunnel {
                o["up"] = t.up
                if let ms = t.ms { o["ms"] = ms }
                o["host"] = t.host
                if let port = t.port { o["port"] = port }
                if !t.up { down = true }
            }
            if let d = r.deploy {
                o["health"] = d.health
                o["up"] = d.up
                if let ms = d.avgMs { o["ms"] = ms }
                if let u = d.openUrl { o["url"] = u }
                if !d.checks.isEmpty { o["via"] = d.checks.map(\.name) }
                if !d.up { down = true }
            }
            rows.append(o)
        }
        emit(["checks": rows])
        if down { exit(1) }
    }

    private static func action(_ rest: [String]) {
        let yes = rest.contains("--yes")
        let rest = rest.filter { $0 != "--yes" }
        guard rest.count >= 2 else { fail("usage: tiny-status action <id> <name>", code: 2) }
        let id = rest[0]
        let name = rest[1]
        guard let check = checks().first(where: { $0.id == id }) else { fail("no check \(id)") }
        guard let act = check.resolvedActions().first(where: { $0.id == name }) else {
            let ids = check.resolvedActions().map(\.id).joined(separator: ", ")
            fail("no action \(name) on \(id). Have: \(ids.isEmpty ? "(none)" : ids)")
        }
        if let msg = act.confirm, !msg.isEmpty, !yes {
            fail("action \(name) requires confirmation. Re-run with --yes")
        }
        if let url = act.url, !url.isEmpty {
            guard let u = URL(string: url) else { fail("bad url") }
            let ok = NSWorkspaceOpen.url(u)
            emit(["ok": ok, "id": id, "action": name, "url": url])
            return
        }
        guard let cmd = act.command, !cmd.isEmpty else { fail("action \(name) has no command or url") }
        let code = Shell.run(cmd, timeout: 90)
        emit(["ok": code == 0, "id": id, "action": name, "exit": Int(code)])
        if code != 0 { exit(1) }
    }

    private static func setEnabled(_ rest: [String], _ on: Bool) {
        guard let id = rest.first, !id.isEmpty else { fail("usage: tiny-status \(on ? "enable" : "disable") <id>", code: 2) }
        patchEnabled(id, on)
        emit(["ok": true, "id": id, "enabled": on])
    }

    private static func toggle(_ rest: [String]) {
        guard let id = rest.first, !id.isEmpty else { fail("usage: tiny-status toggle <id>", code: 2) }
        guard let c = checks().first(where: { $0.id == id }) else { fail("no check \(id)") }
        let on = !c.isEnabled
        patchEnabled(id, on)
        emit(["ok": true, "id": id, "enabled": on])
    }

    private static func patchEnabled(_ id: String, _ on: Bool) {
        var root = loadRoot()
        guard allIds(root).contains(id) else { fail("no check \(id)") }
        for key in ["checks", "tunnels", "deployments"] {
            guard var arr = root[key] as? [[String: Any]] else { continue }
            for i in arr.indices where arr[i]["id"] as? String == id {
                arr[i]["enabled"] = on
            }
            root[key] = arr
        }
        saveRoot(root)
    }

    private static func checks() -> [Check] {
        let cfg = ConfigLoader.load()
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

    private static func row(_ c: Check, cache: CacheFile?) -> [String: Any] {
        var o: [String: Any] = [
            "id": c.id,
            "title": c.title,
            "kind": c.kind.rawValue,
            "actions": c.resolvedActions().map(\.id),
            "enabled": c.isEnabled,
        ]
        if let t = c.tags { o["tags"] = t }
        if let g = c.group { o["group"] = g }
        if let i = c.icon { o["icon"] = i }
        if let i = c.image { o["image"] = i }
        if let u = c.openUrl { o["openUrl"] = u }
        if let d = c.discover { o["discover"] = d }
        if let u = c.url { o["url"] = u }
        if let h = c.host { o["host"] = h }
        if let p = c.port { o["port"] = p }
        if c.kind == .tcp {
            if let up = cache?.tunnels[c.id] { o["up"] = up }
        } else if let d = cache?.deploys[c.id] {
            o["health"] = d.health
            o["up"] = d.health == "healthy"
        }
        return o
    }

    private static func loadRoot() -> [String: Any] {
        let url = ConfigLoader.userURL
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return obj
        }
        return [:]
    }

    private static func saveRoot(_ root: [String: Any]) {
        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        else { fail("could not encode config") }
        do {
            try FileManager.default.createDirectory(
                at: ConfigLoader.userURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try out.write(to: ConfigLoader.userURL, options: .atomic)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func checkArrays(_ root: [String: Any]) -> (checks: [[String: Any]], ids: [String]) {
        (root["checks"] as? [[String: Any]] ?? [], allIds(root))
    }

    private static func allIds(_ root: [String: Any]) -> [String] {
        func ids(_ key: String) -> [String] {
            (root[key] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        }
        var seen = Set<String>()
        var out: [String] = []
        for id in ids("checks") + ids("tunnels") + ids("deployments") where seen.insert(id).inserted {
            out.append(id)
        }
        return out
    }

    private static func iso(_ d: Date?) -> Any {
        guard let d else { return NSNull() }
        let f = ISO8601DateFormatter()
        return f.string(from: d)
    }

    private static func emit(_ obj: Any) {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8)
        else { fputs("json encode failed\n", stderr); exit(1) }
        print(s)
    }

    private static func fail(_ msg: String, code: Int32 = 1) -> Never {
        emit(["ok": false, "error": msg])
        exit(code)
    }
}

private enum NSWorkspaceOpen {
    static func url(_ u: URL) -> Bool {
        ProcessInfo.processInfo.environment["TINYSTATUS_CLI_NO_OPEN"] != nil
            ? true
            : {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = [u.absoluteString]
                do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 }
                catch { return false }
            }()
    }
}
