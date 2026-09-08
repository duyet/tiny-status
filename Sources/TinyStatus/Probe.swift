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
            let r = TCP.probe(host: host, port: port)
            info.up = r.ok
            info.ms = r.ms
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
        var uptime: Double?
        if let url = d.healthUrl {
            let hit = HTTP.getJSON(url, timeout: 18)
            if let json = hit.json {
                health = (json["status"] as? String) ?? "unknown"
                live = (json["version"] as? String) ?? "—"
                uptime = num(json["uptime_seconds"])
                if let arr = json["checks"] as? [[String: Any]] {
                    checks = arr.map {
                        CheckRow(
                            name: ($0["service"] as? String) ?? ($0["name"] as? String) ?? "?",
                            status: ($0["status"] as? String) ?? "?",
                            ms: num($0["response_time_ms"]) ?? num($0["latency_ms"])
                        )
                    }
                }
                if checks.isEmpty {
                    checks = [CheckRow(name: "http", status: health == "healthy" ? "healthy" : health, ms: hit.ms)]
                }
            } else if let code = hit.code, (200..<300).contains(code) {
                health = "healthy"
                checks = [CheckRow(name: "http", status: "healthy", ms: hit.ms)]
            } else {
                health = "down"
                checks = [CheckRow(name: "http", status: "unhealthy", ms: hit.ms)]
            }
        }
        let k8s = tag(Shell.output(d.k8s ?? [], timeout: 20))
        let k8sLive = tag(Shell.output(d.k8sLive ?? [], timeout: 20))
        return DeployRow(
            id: d.id, title: d.title, health: health, liveVersion: live,
            k8sVersion: k8s, k8sLiveVersion: k8sLive, checks: checks, openUrl: d.openUrl,
            uptime: uptime
        )
    }

    static func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    static func check(_ c: Check, discoverPaths: [String]? = nil) -> (tunnel: TunnelInfo?, deploy: DeployRow?) {
        switch c.kind {
        case .tcp:
            let t = Tunnel(
                id: c.id, title: c.title, status: nil,
                start: c.start, stop: c.stop, open: c.open,
                probeHost: c.host, probePort: c.port
            )
            return (tunnel(t), nil)
        case .http:
            return (nil, http(c, paths: HealthDiscover.paths(check: c, config: discoverPaths)))
        case .command:
            let code = Shell.run(c.command ?? ["/usr/bin/true"], timeout: 20)
            let row = DeployRow(
                id: c.id, title: c.title,
                health: code == 0 ? "healthy" : "unhealthy",
                liveVersion: "—", k8sVersion: "—", k8sLiveVersion: "—",
                checks: [CheckRow(name: "command", status: code == 0 ? "healthy" : "unhealthy")],
                openUrl: nil
            )
            return (nil, row)
        }
    }

    private static func http(_ c: Check, paths: [String]) -> DeployRow {
        let k8s = tag(Shell.output(c.k8s ?? [], timeout: 20))
        let k8sLive = tag(Shell.output(c.k8sLive ?? [], timeout: 20))
        func row(_ health: String, live: String, checks: [CheckRow], url: String?, uptime: Double? = nil) -> DeployRow {
            DeployRow(
                id: c.id, title: c.title, health: health, liveVersion: live,
                k8sVersion: k8s, k8sLiveVersion: k8sLive, checks: checks,
                openUrl: url ?? c.openUrl ?? c.url, uptime: uptime
            )
        }
        func fromHit(_ hit: (json: [String: Any]?, code: Int?, ms: Double), url: String) -> DeployRow? {
            guard HTTP.isHealthy(json: hit.json, code: hit.code) else { return nil }
            var health = "healthy"
            var live = "—"
            var uptime: Double?
            var checks: [CheckRow] = []
            if let json = hit.json {
                if let s = json["status"] as? String {
                    let n = s.lowercased()
                    health = ["ok", "up", "pass", "passing", "success", "healthy"].contains(n) ? "healthy" : n
                }
                live = (json["version"] as? String) ?? "—"
                uptime = num(json["uptime_seconds"])
                if let arr = json["checks"] as? [[String: Any]] {
                    checks = arr.map {
                        CheckRow(
                            name: ($0["service"] as? String) ?? ($0["name"] as? String) ?? "?",
                            status: ($0["status"] as? String) ?? "?",
                            ms: num($0["response_time_ms"]) ?? num($0["latency_ms"])
                        )
                    }
                }
            }
            if checks.isEmpty {
                let path = URL(string: url)?.path ?? "http"
                checks = [CheckRow(name: path.isEmpty || path == "/" ? "http" : path, status: health, ms: hit.ms)]
            }
            return row(health, live: live, checks: checks, url: url, uptime: uptime)
        }
        func down(_ ms: Double? = nil) -> DeployRow {
            row("down", live: "—", checks: [CheckRow(name: "http", status: "unhealthy", ms: ms)], url: c.openUrl ?? c.url)
        }
        guard let start = c.url, let base = URL(string: start), base.host != nil else { return down() }
        if HealthDiscover.wantsDiscover(c) {
            let origin = base.originURL
            let explicit = !base.path.isEmpty && base.path != "/"
            if explicit, let r = fromHit(HTTP.getJSON(start, timeout: 8), url: start) { return r }
            for p in paths {
                let u = p.isEmpty ? origin.absoluteString : origin.absoluteString.trimmingSuffix("/") + p
                if let r = fromHit(HTTP.getJSON(u, timeout: 4), url: u) { return r }
            }
            if !paths.contains(""), let r = fromHit(HTTP.getJSON(origin.absoluteString, timeout: 4), url: origin.absoluteString) {
                return r
            }
            if HealthDiscover.pingEnabled(c), let host = origin.host {
                let port = origin.port ?? (origin.scheme == "http" ? 80 : 443)
                let tcp = TCP.probe(host: host, port: port)
                let st = tcp.ok ? "healthy" : "unhealthy"
                return row(
                    tcp.ok ? "healthy" : "down",
                    live: "tcp",
                    checks: [CheckRow(name: "tcp", status: st, ms: tcp.ms)],
                    url: c.openUrl ?? c.url
                )
            }
            return down()
        }
        if let r = fromHit(HTTP.getJSON(start, timeout: 18), url: start) { return r }
        return down()
    }

    static func tag(_ image: String) -> String {
        let s = image.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "—" }
        if let i = s.lastIndex(of: ":") { return String(s[s.index(after: i)...]) }
        return s
    }
}

enum HTTP {
    static func isHealthy(json: [String: Any]?, code: Int?) -> Bool {
        if let json {
            if let s = json["status"] as? String {
                let n = s.lowercased()
                if ["unhealthy", "down", "fail", "failed", "error", "critical"].contains(n) { return false }
                if ["healthy", "ok", "up", "pass", "passing", "success"].contains(n) { return true }
            }
            if let h = json["healthy"] as? Bool { return h }
        }
        if let code, (200..<300).contains(code) { return true }
        return false
    }

    static func getJSON(_ url: String, timeout: TimeInterval) -> (json: [String: Any]?, code: Int?, ms: Double) {
        guard let u = URL(string: url) else { return (nil, nil, 0) }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.setValue("text/html,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any]?
        var code: Int?
        let t0 = CFAbsoluteTimeGetCurrent()
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            code = (resp as? HTTPURLResponse)?.statusCode
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                out = obj
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 1)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        return (out, code, ms)
    }
}

enum TCP {
    static func probe(host: String, port: Int, timeoutSec: Double = 1.5) -> (ok: Bool, ms: Double) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let ok = canConnect(host: host, port: port, timeoutSec: timeoutSec)
        return (ok, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }

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
