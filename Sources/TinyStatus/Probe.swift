import Darwin
import Foundation

enum Probe {
    static func tunnel(_ t: Tunnel) -> TunnelInfo {
        let host = t.probeHost ?? "127.0.0.1"
        var info = TunnelInfo(
            up: false, host: host, port: t.probePort,
            pid: nil, process: nil, elapsed: nil, command: nil
        )
        if let port = t.probePort {
            info.up = TCP.canConnect(host: host, port: port)
            if info.up { fillListen(&info, host: host, port: port) }
            return info
        }
        if let status = t.status, !status.isEmpty {
            info.up = Shell.run(status, timeout: 12) == 0
        }
        return info
    }

    private static func fillListen(_ info: inout TunnelInfo, host: String, port: Int) {
        let lsof = Shell.capture(
            ["/usr/sbin/lsof", "-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "pc"],
            timeout: 4
        ).1
        var pid: String?
        var proc: String?
        for line in lsof.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("p") { pid = String(line.dropFirst()) }
            if line.hasPrefix("c") { proc = String(line.dropFirst()) }
        }
        info.pid = pid
        info.process = proc
        guard let pid else { return }
        let ps = Shell.capture(
            ["/bin/ps", "-p", pid, "-o", "etime=,command="],
            timeout: 4
        ).1.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ps.isEmpty else { return }
        let parts = ps.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 2 {
            info.elapsed = parts[0]
            info.command = parts[1]
        } else {
            info.command = ps
        }
    }

    static func deployment(_ d: Deployment) -> DeployRow {
        var live = "—"
        var health = "down"
        var checks: [CheckRow] = []
        if let url = d.healthUrl, let json = HTTP.getJSON(url, timeout: 18) {
            health = (json["status"] as? String) ?? "unknown"
            live = (json["version"] as? String) ?? "—"
            if let arr = json["checks"] as? [[String: Any]] {
                checks = arr.map {
                    CheckRow(
                        name: ($0["service"] as? String) ?? "?",
                        status: ($0["status"] as? String) ?? "?"
                    )
                }
            }
        }
        let k8s = tag(Shell.output(d.k8s ?? [], timeout: 20))
        let k8sLive = tag(Shell.output(d.k8sLive ?? [], timeout: 20))
        return DeployRow(
            id: d.id, title: d.title, health: health, liveVersion: live,
            k8sVersion: k8s, k8sLiveVersion: k8sLive, checks: checks, openUrl: d.openUrl
        )
    }

    static func tag(_ image: String) -> String {
        let s = image.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "—" }
        if let i = s.lastIndex(of: ":") { return String(s[s.index(after: i)...]) }
        return s
    }
}

enum HTTP {
    static func getJSON(_ url: String, timeout: TimeInterval) -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any]?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                out = obj
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 1)
        return out
    }
}

enum TCP {
    static func canConnect(host: String, port: Int, timeoutSec: Double = 1.5) -> Bool {
        var hints = addrinfo(
            ai_flags: AI_NUMERICHOST,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let first = info else {
            return false
        }
        defer { freeaddrinfo(first) }
        let fd = socket(first.pointee.ai_family, first.pointee.ai_socktype, first.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        _ = connect(fd, first.pointee.ai_addr, first.pointee.ai_addrlen)
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, Int32(timeoutSec * 1000)) > 0 else { return false }
        var soErr: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &len)
        return soErr == 0
    }
}
