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

/// Stable pastel for a tag, in the same spirit as shadcn Badge (soft fill + saturated label).
enum TagTint {
    enum Slot: String, CaseIterable {
        case blue, green, sky, purple, red, orange, yellow, gray
    }

    static func slot(_ tag: String) -> Slot {
        let n = tag.lowercased()
        if ["prod", "production", "live", "down", "error"].contains(n) { return .red }
        if ["staging", "stage", "warn", "warning"].contains(n) { return .orange }
        if ["dev", "development", "up", "ok"].contains(n) { return .green }
        if ["tunnel", "tcp", "ssh"].contains(n) { return .blue }
        if ["http", "web", "api"].contains(n) { return .sky }
        if ["command", "cli", "script"].contains(n) { return .purple }
        if ["eu"].contains(n) { return .blue }
        if ["sg"].contains(n) { return .green }
        if ["za"].contains(n) { return .yellow }
        if ["us", "uk"].contains(n) { return .purple }
        var h: UInt64 = 5381
        for b in n.utf8 { h = ((h << 5) &+ h) &+ UInt64(b) }
        let all = Slot.allCases
        return all[Int(h % UInt64(all.count))]
    }

    static func colors(_ tag: String) -> (bg: NSColor, fg: NSColor) {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch slot(tag) {
        case .blue: return pair(dark, 0.82, 0.90, 0.99, 0.12, 0.38, 0.82, 0.18, 0.32, 0.52, 0.62, 0.78, 1.0)
        case .green: return pair(dark, 0.84, 0.95, 0.88, 0.08, 0.48, 0.30, 0.14, 0.32, 0.24, 0.52, 0.88, 0.68)
        case .sky: return pair(dark, 0.84, 0.95, 0.98, 0.04, 0.52, 0.68, 0.12, 0.32, 0.40, 0.55, 0.88, 0.95)
        case .purple: return pair(dark, 0.93, 0.88, 0.98, 0.45, 0.22, 0.72, 0.28, 0.20, 0.42, 0.82, 0.70, 1.0)
        case .red: return pair(dark, 0.99, 0.90, 0.90, 0.72, 0.14, 0.18, 0.42, 0.16, 0.18, 1.0, 0.70, 0.72)
        case .orange: return pair(dark, 1.0, 0.93, 0.85, 0.72, 0.38, 0.04, 0.42, 0.26, 0.10, 1.0, 0.78, 0.50)
        case .yellow: return pair(dark, 1.0, 0.96, 0.82, 0.62, 0.48, 0.04, 0.40, 0.34, 0.10, 0.98, 0.88, 0.45)
        case .gray: return pair(dark, 0.93, 0.93, 0.95, 0.32, 0.32, 0.36, 0.28, 0.28, 0.30, 0.82, 0.82, 0.84)
        }
    }

    private static func pair(
        _ dark: Bool,
        _ lr: CGFloat, _ lg: CGFloat, _ lb: CGFloat,
        _ lfr: CGFloat, _ lfg: CGFloat, _ lfb: CGFloat,
        _ dr: CGFloat, _ dg: CGFloat, _ db: CGFloat,
        _ dfr: CGFloat, _ dfg: CGFloat, _ dfb: CGFloat
    ) -> (NSColor, NSColor) {
        if dark {
            return (NSColor(srgbRed: dr, green: dg, blue: db, alpha: 1), NSColor(srgbRed: dfr, green: dfg, blue: dfb, alpha: 1))
        }
        return (NSColor(srgbRed: lr, green: lg, blue: lb, alpha: 1), NSColor(srgbRed: lfr, green: lfg, blue: lfb, alpha: 1))
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
    /// Missing or true = notify on fail/recover (still subject to global `alerts`). false = mute this check.
    var alert: Bool?

    var isEnabled: Bool { enabled != false }
    var wantsAlert: Bool { alert != false }

    /// Whether to post a notification for this check's new state.
    static func shouldAlert(
        globalEnabled: Bool,
        onDown: Bool,
        onRecover: Bool,
        checkAlert: Bool?,
        enabled: Bool,
        wasUp: Bool?,
        isUp: Bool
    ) -> String? {
        guard globalEnabled, enabled, checkAlert != false else { return nil }
        guard let wasUp else { return nil }
        if wasUp, !isUp { return onDown ? "down" : nil }
        if !wasUp, isUp { return onRecover ? "recover" : nil }
        return nil
    }

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
            tags: t.tags, group: t.group, icon: t.icon, image: t.image, enabled: t.enabled, alert: t.alert
        )
    }

    static func from(deployment d: Deployment) -> Check {
        Check(
            id: d.id, title: d.title, kind: .http,
            url: d.healthUrl, k8s: d.k8s, k8sLive: d.k8sLive, openUrl: d.openUrl,
            tags: d.tags, group: d.group, icon: d.icon, image: d.image, enabled: d.enabled, alert: d.alert
        )
    }
}
