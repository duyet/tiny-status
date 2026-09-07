import Foundation
import SwiftUI

struct Alerts: Codable {
    var enabled: Bool?
    var onDown: Bool?
    var onRecover: Bool?
    var onVersionDrift: Bool?
    var cooldownSeconds: Double?
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
    var alerts: Alerts?
    var backup: Backup?
    var tunnels: [Tunnel]?
    var deployments: [Deployment]?
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
    var lastAlert: [String: Date]
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
}

struct Deployment: Codable, Identifiable {
    var id: String
    var title: String
    var healthUrl: String?
    var k8s: [String]?
    var k8sLive: [String]?
    var openUrl: String?
}

struct TunnelInfo: Sendable {
    var up: Bool
    var host: String
    var port: Int?
    var pid: String?
    var process: String?
    var elapsed: String?
    var command: String?
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
}

struct CheckRow: Identifiable {
    var id: String { name }
    var name: String
    var status: String
    var ms: Double? = nil
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
