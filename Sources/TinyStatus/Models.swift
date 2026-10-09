import Foundation
import SwiftUI

/// Global `alerts` and per-check `alert` object. Per-check fields override global ones.
struct Alerts: Codable, Equatable, Sendable {
    var enabled: Bool?
    var onDown: Bool?
    var onVersionDrift: Bool?
    /// Consecutive failed polls before alerting.
    var after: Int?
    /// Notify on recovery (only if a down alert was sent).
    var recover: Bool?
    /// Seconds before re-alerting while still down. 0 = never.
    var `repeat`: Double?
    /// Local `HH:MM-HH:MM` window where alerts are delivered without sound.
    var quiet: String?
    var sound: Bool?
}

/// Per-check `alert`: `false` / `true`, or an `Alerts` object merged over the global one.
enum AlertSetting: Codable, Equatable, Sendable {
    case flag(Bool)
    case rule(Alerts)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .flag(b) } else { self = .rule(try c.decode(Alerts.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .flag(b): try c.encode(b)
        case let .rule(a): try c.encode(a)
        }
    }

    var isOn: Bool {
        switch self {
        case let .flag(b): b
        case let .rule(a): a.enabled != false
        }
    }
}

struct Backup: Codable {
    var enabled: Bool?
    var repo: String?
    var file: String?
    var remote: String?
    var branch: String?
    var remoteUrl: String?
    var autoOnSave: Bool?
}

struct Config: Codable {
    var pollSeconds: Double?
    var vars: [String: String]?
    var groupBy: String?
    var density: String?
    var groups: [String]?
    var order: [String]?
    var discoverPaths: [String]?
    var alerts: Alerts?
    var backup: Backup?
    var tunnels: [Tunnel]?
    var deployments: [Deployment]?
    var checks: [Check]?
}

struct CachedDeploy: Codable {
    var health: String
    var liveVersion: String
    var k8sVersion: String
    var k8sLiveVersion: String
    var spark: [Double]?
}

struct CacheFile: Codable {
    var tunnels: [String: Bool]
    var deploys: [String: CachedDeploy]
    var lastChecked: Date?
}

struct Tunnel: Codable, Identifiable {
    var id: String
    var title: String
    var status: [String]?
    var start: [String]?
    var stop: [String]?
    var open: [String]?
    /// External signal: TCP connect. Independent of who started the tunnel.
    var probeHost: String?
    var probePort: Int?
    var tags: [String]?
    var group: String?
    var icon: String?
    var image: String?
    var enabled: Bool?
    var alert: Bool?
}

struct Deployment: Codable, Identifiable {
    var id: String
    var title: String
    var healthUrl: String?
    var k8s: [String]?
    var k8sLive: [String]?
    var openUrl: String?
    var tags: [String]?
    var group: String?
    var icon: String?
    var image: String?
    var enabled: Bool?
    var alert: Bool?
}

struct TunnelInfo: Sendable {
    var up: Bool
    var host: String
    var port: Int?
    var pid: String?
    var process: String?
    var elapsed: String?
    var command: String?
    var ms: Double? = nil
}

struct TunnelRow: Identifiable {
    var id: String
    var title: String
    var up: Bool
    var busy: Bool
    var host: String = "127.0.0.1"
    var port: Int? = nil
    var pid: String? = nil
    var process: String? = nil
    var elapsed: String? = nil
    var command: String? = nil
    var canStart = false
    var canStop = false
    var canOpen = false
    var actions: [CheckAction] = []
    var spark: [Double] = []
    var ms: Double? = nil
    var tags: [String] = []
    var group: String = "Other"
    var icon: String? = nil
    var image: String? = nil
    var enabled: Bool = true
}

struct CheckRow: Identifiable {
    var id: String { name }
    var name: String
    var status: String
    var ms: Double? = nil
    var spark: [Double] = []
}

struct DeployRow: Identifiable {
    var id: String
    var title: String
    var health: String
    var liveVersion: String
    var k8sVersion: String
    var k8sLiveVersion: String
    var checks: [CheckRow]
    var openUrl: String?
    var spark: [Double] = []
    var uptime: Double? = nil
    var tags: [String] = []
    var group: String = "Other"
    var actions: [CheckAction] = []
    var icon: String? = nil
    var image: String? = nil
    var enabled: Bool = true
    var up: Bool { health == "healthy" }

    static func healthScore(_ health: String) -> Double {
        switch health {
        case "healthy": 1
        case "degraded": 0.5
        default: 0
        }
    }
    var okCount: Int { checks.filter { $0.status == "healthy" }.count }
    var avgMs: Double? {
        let xs = checks.compactMap(\.ms)
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }
}
