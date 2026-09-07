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
        cfg.tunnels = cfg.tunnels?.map { t in
            var t = t
            t.status = t.status?.map(expand)
            t.start = t.start?.map(expand)
            t.stop = t.stop?.map(expand)
            t.open = t.open?.map(expand)
            t.probeHost = t.probeHost.map(expand)
            return t
        }
        if var b = cfg.backup {
            b.repo = b.repo.map(expand)
            b.remoteUrl = b.remoteUrl.map(expand)
            cfg.backup = b
        }
        cfg.deployments = cfg.deployments?.map { d in
            var d = d
            d.healthUrl = d.healthUrl.map(expand)
            d.k8s = d.k8s?.map(expand)
            d.k8sLive = d.k8sLive?.map(expand)
            d.openUrl = d.openUrl.map(expand)
            return d
        }
        return cfg
    }

    static func expand(_ s: String) -> String {
        s.replacingOccurrences(
            of: "{home}",
            with: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }
}

let exampleJSON = """
{
  "pollSeconds": 30,
  "tunnels": [
    {
      "id": "local",
      "title": "Local",
      "probeHost": "127.0.0.1",
      "probePort": 8080
    }
  ],
  "deployments": [
    {
      "id": "api",
      "title": "API",
      "healthUrl": "https://example.com/health",
      "openUrl": "https://example.com/health"
    }
  ]
}
"""


