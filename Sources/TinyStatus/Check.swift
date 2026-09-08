import AppKit
import Foundation

enum CheckKind: String, Codable, Sendable {
    case http, tcp, command
}

enum GroupBy: String, Codable, CaseIterable {
    case tag, kind, none
}

enum CheckArt {
    static func symbol(icon: String?, kind: CheckKind, enabled: Bool) -> String {
        if !enabled { return "pause.circle" }
        if let icon, !icon.isEmpty { return icon }
        switch kind {
        case .tcp: return "network"
        case .http: return "globe"
        case .command: return "terminal"
        }
    }

    static func nsImage(_ name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        let path = ConfigLoader.expand(name)
        if path.contains("/") {
            return NSImage(contentsOfFile: path)
        }
        if let img = NSImage(named: path) { return img }
        let base = (path as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        if !ext.isEmpty,
           let url = Bundle.main.url(forResource: base, withExtension: ext)
        {
            return NSImage(contentsOf: url)
        }
        return Bundle.main.url(forResource: path, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }
}

struct CheckAction: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var command: [String]?
    var url: String?
    /// `always` (default), `up`, or `down`.
    var when: String?
    var icon: String?
    var confirm: String?

    func isVisible(up: Bool) -> Bool {
        switch when ?? "always" {
        case "up": return up
        case "down": return !up
        default: return true
        }
    }
}

enum Tags {
    static func inferred(title: String, kind: CheckKind) -> [String] {
        let n = title.lowercased()
        var out: [String] = []
        if kind == .tcp { out.append("Tunnel") }
        for (key, label) in [("sg", "SG"), ("eu", "EU"), ("za", "ZA")] where n.contains(key) {
            out.append(label)
        }
        for env in ["prod", "staging", "dev"] where n.contains(env) {
            out.append(env)
        }
        if out.isEmpty { out.append("Other") }
        return out
    }

    static func resolved(_ c: Check) -> [String] {
        if let t = c.tags?.map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }), !t.isEmpty {
            return t
        }
        return inferred(title: c.title, kind: c.kind)
    }

    static func group(_ c: Check) -> String {
        if let g = c.group?.trimmingCharacters(in: .whitespaces), !g.isEmpty { return g }
        return resolved(c).first ?? "Other"
    }
}

struct Check: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var kind: CheckKind
    var url: String?
    var host: String?
    var port: Int?
    var command: [String]?
    var discover: Bool?
    /// Override the global / default health path list.
    var discoverPaths: [String]?
    /// After HTTP paths fail, TCP-connect the host (default true when discovering).
    var ping: Bool?
    var k8s: [String]?
    var k8sLive: [String]?
    var openUrl: String?
    var start: [String]?
    var stop: [String]?
    var open: [String]?
    var actions: [CheckAction]?
    var tags: [String]?
    var group: String?
    /// SF Symbol name. Falls back by kind if omitted.
    var icon: String?
    /// Bundled image name (`GitLab`) or a file path (`{config}/gitlab.png`).
    var image: String?
    /// Missing or true = probed. false = skip probe, still listed.
    var enabled: Bool?

    var isEnabled: Bool { enabled != false }

    /// Config `actions[]`, plus legacy `start` / `stop` / `open` if no list is set.
    func resolvedActions() -> [CheckAction] {
        if let actions, !actions.isEmpty { return actions }
        var out: [CheckAction] = []
        if let start {
            out.append(CheckAction(id: "start", title: "Connect", command: start, when: "down", icon: "play.fill"))
        }
        if let stop {
            out.append(CheckAction(id: "stop", title: "Disconnect", command: stop, when: "up", icon: "stop.fill"))
        }
        if let open {
            out.append(CheckAction(id: "open", title: "Open", command: open, when: "up", icon: "arrow.up.right.square"))
        }
        return out
    }

    static func from(tunnel t: Tunnel) -> Check {
        Check(
            id: t.id, title: t.title, kind: .tcp,
            host: t.probeHost ?? "127.0.0.1", port: t.probePort,
            start: t.start, stop: t.stop, open: t.open,
            tags: t.tags, group: t.group, icon: t.icon, image: t.image, enabled: t.enabled
        )
    }

    static func from(deployment d: Deployment) -> Check {
        Check(
            id: d.id, title: d.title, kind: .http,
            url: d.healthUrl, k8s: d.k8s, k8sLive: d.k8sLive, openUrl: d.openUrl,
            tags: d.tags, group: d.group, icon: d.icon, image: d.image, enabled: d.enabled
        )
    }
}
