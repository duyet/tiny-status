import AppKit
import Combine
import Foundation
import Network

struct NetSnap: Equatable {
    var online: Bool
    var title: String
    var symbol: String
    var detail: String

    static let offline = NetSnap(online: false, title: "Offline", symbol: "wifi.slash", detail: "No route")
}

struct TailSnap: Equatable {
    var installed: Bool
    var up: Bool
    var title: String
    var symbol: String
    var detail: String

    static let missing = TailSnap(
        installed: false, up: false, title: "Tailscale",
        symbol: "circle.dotted", detail: "Not installed"
    )
}

enum TailscaleStatus {
    static let binaries = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
    ]

    static func parse(_ json: [String: Any]) -> TailSnap {
        let backend = ((json["BackendState"] as? String) ?? "").lowercased()
        let selfObj = json["Self"] as? [String: Any]
        let host = (selfObj?["HostName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selfOnline = selfObj?["Online"] as? Bool
        let running = backend == "running" || selfOnline == true
        if backend == "needslogin" || backend == "needs-login" {
            return TailSnap(installed: true, up: false, title: "Tailscale", symbol: "person.crop.circle.badge.questionmark", detail: "Needs login")
        }
        if backend == "stopped" || backend == "stopping" {
            return TailSnap(installed: true, up: false, title: "Tailscale", symbol: "pause.circle", detail: "Stopped")
        }
        if backend == "starting" {
            return TailSnap(installed: true, up: false, title: "Tailscale", symbol: "ellipsis.circle", detail: "Starting")
        }
        if running {
            let name = (host?.isEmpty == false) ? host! : "Up"
            return TailSnap(installed: true, up: true, title: "Tailscale", symbol: "circle.fill", detail: name)
        }
        let label = backend.isEmpty ? "Unknown" : backend.capitalized
        return TailSnap(installed: true, up: false, title: "Tailscale", symbol: "exclamationmark.circle", detail: label)
    }

    static func probe() -> TailSnap {
        guard let bin = binaries.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return .missing
        }
        let out = Shell.output([bin, "status", "--json"], timeout: 3)
        guard let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            if out.lowercased().contains("stopped") {
                return TailSnap(installed: true, up: false, title: "Tailscale", symbol: "pause.circle", detail: "Stopped")
            }
            return TailSnap(installed: true, up: false, title: "Tailscale", symbol: "questionmark.circle", detail: "Unavailable")
        }
        return parse(obj)
    }
}

enum NetStatus {
    static func snap(_ path: NWPath) -> NetSnap {
        guard path.status == .satisfied else { return .offline }
        let title: String
        let symbol: String
        if path.usesInterfaceType(.wifi) {
            title = "Wi-Fi"
            symbol = "wifi"
        } else if path.usesInterfaceType(.wiredEthernet) {
            title = "Ethernet"
            symbol = "cable.connector"
        } else if path.usesInterfaceType(.cellular) {
            title = "Cellular"
            symbol = "antenna.radiowaves.left.and.right"
        } else {
            title = "Online"
            symbol = "network"
        }
        var bits: [String] = []
        if path.isExpensive { bits.append("expensive") }
        if path.isConstrained { bits.append("constrained") }
        if path.supportsIPv6 { bits.append("IPv6") }
        else if path.supportsIPv4 { bits.append("IPv4") }
        return NetSnap(online: true, title: title, symbol: symbol, detail: bits.isEmpty ? "On" : bits.joined(separator: " · "))
    }
}

final class LinkStatus: ObservableObject {
    static let shared = LinkStatus()

    @Published var net = NetSnap.offline
    @Published var tail = TailSnap.missing

    private let monitor = NWPathMonitor()
    private var timer: Timer?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let snap = NetStatus.snap(path)
            DispatchQueue.main.async { self?.net = snap }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        refreshTail()
        let t = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.refreshTail()
        }
        t.tolerance = 4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refreshTail() {
        Task.detached { [weak self] in
            let snap = TailscaleStatus.probe()
            await MainActor.run { [weak self] in self?.tail = snap }
        }
    }
}

