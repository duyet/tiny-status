import Foundation
import UserNotifications


enum Notify {
    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(id: String, title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(
            identifier: "net.duyet.tiny-status.\(id)", content: c, trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}

enum DiskCache {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tiny-status/cache.json")
    }

    static func load() -> CacheFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(CacheFile.self, from: data)
    }

    static func save(_ snap: CacheFile) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(snap) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

enum ConfigLoader {
    static var userURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tiny-status/tunnels.json")
    }

    static func mtime() -> Date? {
        try? userURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func load() -> Config {
        let url = userURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? exampleJSON.data(using: .utf8)?.write(to: url)
        }
        guard let data = try? Data(contentsOf: url),
              var cfg = try? JSONDecoder().decode(Config.self, from: data)
        else { return Config() }
        lastTable = Vars.table(cfg.vars)
        cfg.tunnels = cfg.tunnels?.map { t in
            var t = t
            t.title = expand(t.title)
            t.status = t.status?.map(expand)
            t.start = t.start?.map(expand)
            t.stop = t.stop?.map(expand)
            t.open = t.open?.map(expand)
            t.probeHost = t.probeHost.map(expand)
            t.tags = t.tags?.map(expand)
            t.group = t.group.map(expand)
            t.icon = t.icon.map(expand)
            t.image = t.image.map(expand)
            return t
        }
        if var b = cfg.backup {
            b.repo = b.repo.map(expand)
            b.remoteUrl = b.remoteUrl.map(expand)
            cfg.backup = b
        }
        cfg.deployments = cfg.deployments?.map { d in
            var d = d
            d.title = expand(d.title)
            d.healthUrl = d.healthUrl.map(expand)
            d.k8s = d.k8s?.map(expand)
            d.k8sLive = d.k8sLive?.map(expand)
            d.openUrl = d.openUrl.map(expand)
            d.tags = d.tags?.map(expand)
            d.group = d.group.map(expand)
            d.icon = d.icon.map(expand)
            d.image = d.image.map(expand)
            return d
        }
        cfg.checks = cfg.checks?.map { c in
            var c = c
            c.title = expand(c.title)
            c.url = c.url.map(expand)
            c.host = c.host.map(expand)
            c.command = c.command?.map(expand)
            c.k8s = c.k8s?.map(expand)
            c.k8sLive = c.k8sLive?.map(expand)
            c.openUrl = c.openUrl.map(expand)
            c.start = c.start?.map(expand)
            c.stop = c.stop?.map(expand)
            c.open = c.open?.map(expand)
            c.actions = c.actions?.map { a in
                var a = a
                a.title = expand(a.title)
                a.command = a.command?.map(expand)
                a.url = a.url.map(expand)
                a.confirm = a.confirm.map(expand)
                return a
            }
            c.tags = c.tags?.map(expand)
            c.group = c.group.map(expand)
            c.icon = c.icon.map(expand)
            c.image = c.image.map(expand)
            return c
        }
        return cfg
    }

    static var lastTable: [String: String] = [:]

    static func expand(_ s: String) -> String {
        Vars.apply(s, lastTable.isEmpty ? Vars.builtins() : lastTable)
    }
}

enum Vars {
    static func builtins() -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var tmp = NSTemporaryDirectory()
        if tmp.hasSuffix("/") { tmp.removeLast() }
        return [
            "home": home,
            "user": NSUserName(),
            "tmp": tmp,
            "config": ConfigLoader.userURL.deletingLastPathComponent().path,
            "hostname": Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
        ]
    }

    static func table(_ custom: [String: String]?) -> [String: String] {
        var t = builtins()
        for _ in 0..<4 {
            for (k, v) in custom ?? [:] {
                t[k] = apply(v, t)
            }
        }
        return t
    }

    static func apply(_ s: String, _ table: [String: String]) -> String {
        var out = s
        for _ in 0..<8 {
            let prev = out
            out = replaceEnv(out)
            for (k, v) in table {
                out = out.replacingOccurrences(of: "{\(k)}", with: v)
            }
            if out == prev { break }
        }
        return out
    }

    static func replaceEnv(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "\\{env:([^}]+)\\}") else { return s }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var out = s
        for m in matches.reversed() {
            guard m.numberOfRanges >= 2 else { continue }
            let name = ns.substring(with: m.range(at: 1))
            let val = ProcessInfo.processInfo.environment[name] ?? ""
            if let r = Range(m.range, in: out) {
                out.replaceSubrange(r, with: val)
            }
        }
        return out
    }
}

let exampleJSON = """
{
  "pollSeconds": 30,
  "groupBy": "tag",
  "vars": {
    "host": "example.com",
    "health": "https://{host}/health"
  },
  "groups": ["Tunnel", "SG", "EU", "ZA", "Other"],
  "checks": [
    {"id":"web","title":"Web","kind":"http","url":"{health}","discover":true,"tags":["web"],"group":"web"},
    {"id":"local","title":"Local 8080","kind":"tcp","host":"127.0.0.1","port":8080,"tags":["Tunnel"],"group":"Tunnel"}
  ]
}
"""


