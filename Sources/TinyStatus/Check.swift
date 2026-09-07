import Foundation

enum CheckKind: String, Codable, Sendable {
    case http, tcp, command
}

enum GroupBy: String, Codable, CaseIterable {
    case tag, kind, none
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
    var k8s: [String]?
    var k8sLive: [String]?
    var openUrl: String?
    var start: [String]?
    var stop: [String]?
    var open: [String]?
    var tags: [String]?
    var group: String?

    static func from(tunnel t: Tunnel) -> Check {
        Check(
            id: t.id, title: t.title, kind: .tcp,
            host: t.probeHost ?? "127.0.0.1", port: t.probePort,
            start: t.start, stop: t.stop, open: t.open,
            tags: t.tags, group: t.group
        )
    }

    static func from(deployment d: Deployment) -> Check {
        Check(
            id: d.id, title: d.title, kind: .http,
            url: d.healthUrl, k8s: d.k8s, k8sLive: d.k8sLive, openUrl: d.openUrl,
            tags: d.tags, group: d.group
        )
    }
}
