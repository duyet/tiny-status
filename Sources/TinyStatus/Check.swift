import Foundation

enum CheckKind: String, Codable, Sendable {
    case http, tcp, command
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

    static func from(tunnel t: Tunnel) -> Check {
        Check(
            id: t.id, title: t.title, kind: .tcp,
            host: t.probeHost ?? "127.0.0.1", port: t.probePort,
            start: t.start, stop: t.stop, open: t.open
        )
    }

    static func from(deployment d: Deployment) -> Check {
        Check(
            id: d.id, title: d.title, kind: .http,
            url: d.healthUrl, k8s: d.k8s, k8sLive: d.k8sLive, openUrl: d.openUrl
        )
    }
}
