import Darwin
import Foundation

enum Discovery {
    struct Result: Sendable {
        var title: String
        var kind: CheckKind
        var host: String?
        var port: Int?
        var url: String?
        var command: [String]? = nil
        var note: String
        var discover: Bool = false

        func asCheck() -> Check {
            Check(
                id: "\(title)-\(port ?? 0)-\(Int.random(in: 100...999))",
                title: title,
                kind: kind,
                url: url,
                host: host,
                port: port,
                command: command,
                discover: discover ? true : nil
            )
        }
    }

    static func parse(_ paste: String) -> [Result] {
        let trimmed = paste.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if let json = parseJSON(trimmed) { return json }
        var out: [Result] = []
        for line in paste.split(whereSeparator: \.isNewline) {
            let s = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            out.append(contentsOf: parseLine(s))
        }
        return out
    }

    static func probeHTTP(base: URL, timeout: TimeInterval = 5) -> Result? {
        let origin = base.originURL
        let paths = [
            "", "/health", "/healthz", "/ready", "/live", "/ping", "/status",
            "/api/health", "/api/v1/health",
        ]
        for path in paths {
            guard let url = URL(string: path.isEmpty ? origin.absoluteString : origin.absoluteString.trimmingSuffix("/") + path) else {
                continue
            }
            if get(url, timeout: timeout) {
                return Result(
                    title: url.host ?? origin.host ?? url.absoluteString,
                    kind: .http,
                    host: url.host,
                    port: url.port,
                    url: url.absoluteString,
                    note: path.isEmpty ? "root" : path
                )
            }
        }
        return nil
    }

    // MARK: - parse helpers

    private static func parseLine(_ s: String) -> [Result] {
        if let u = URL(string: s), let scheme = u.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"), u.host != nil
        {
            return [Result(
                title: u.host ?? s,
                kind: .http,
                host: u.host,
                port: u.port,
                url: s,
                note: ""
            )]
        }
        if let json = parseJSON(s) { return json }
        if let r = parseBracketIPv6Port(s) { return [r] }
        if let r = parseHostPort(s) { return [r] }
        if isIPv4(s) {
            let note = isTailscale(s) ? "tailscale" : ""
            let ports = isTailscale(s) ? [22, 443] : [443, 80]
            return ports.map {
                Result(title: "\(s):\($0)", kind: .tcp, host: s, port: $0, url: nil, note: note)
            }
        }
        if isIPv6(s) {
            return [443, 80].map {
                Result(title: "[\(s)]:\($0)", kind: .tcp, host: s, port: $0, url: nil, note: "")
            }
        }
        if s.contains("."), isHostname(s) {
            return [
                Result(
                    title: s,
                    kind: .http,
                    host: s,
                    port: nil,
                    url: "https://\(s)",
                    note: ""
                ),
                Result(title: "\(s):443", kind: .tcp, host: s, port: 443, url: nil, note: ""),
            ]
        }
        return []
    }

    private static func parseJSON(_ s: String) -> [Result]? {
        guard let data = s.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = obj as? [String: Any] {
            return mapJSONObject(dict)
        }
        if let arr = obj as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }.flatMap(mapJSONObject)
        }
        return nil
    }

    private static func mapJSONObject(_ d: [String: Any]) -> [Result] {
        if let cmd = commandValue(d["command"]) {
            let title = (d["title"] as? String) ?? cmd.first ?? "command"
            return [Result(title: title, kind: .command, host: nil, port: nil, url: nil, note: cmd.joined(separator: " "))]
        }
        if let urlStr = string(d["url"]), let u = URL(string: urlStr), u.host != nil {
            return [Result(
                title: (d["title"] as? String) ?? (u.host ?? urlStr),
                kind: .http,
                host: u.host,
                port: u.port ?? int(d["port"]),
                url: urlStr,
                note: ""
            )]
        }
        if let host = string(d["host"]), !host.isEmpty {
            let port = int(d["port"])
            if let port {
                return [Result(
                    title: (d["title"] as? String) ?? "\(host):\(port)",
                    kind: .tcp,
                    host: host,
                    port: port,
                    url: nil,
                    note: ""
                )]
            }
            return parseLine(host)
        }
        if let port = int(d["port"]) {
            return [Result(
                title: (d["title"] as? String) ?? "port \(port)",
                kind: .tcp,
                host: string(d["host"]),
                port: port,
                url: nil,
                note: ""
            )]
        }
        return []
    }

    private static func commandValue(_ v: Any?) -> [String]? {
        if let s = v as? String, !s.isEmpty {
            return s.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        if let a = v as? [String], !a.isEmpty { return a }
        if let a = v as? [Any] {
            let s = a.compactMap { $0 as? String }
            return s.isEmpty ? nil : s
        }
        return nil
    }

    private static func parseHostPort(_ s: String) -> Result? {
        guard let colon = s.lastIndex(of: ":") else { return nil }
        let host = String(s[..<colon])
        let portStr = String(s[s.index(after: colon)...])
        guard let port = Int(portStr), port > 0, port <= 65535 else { return nil }
        guard !host.isEmpty, !host.contains(":"), !host.contains("/") else { return nil }
        if isIPv4(host) || isHostname(host) || host == "localhost" {
            let note = isTailscale(host) ? "tailscale" : ""
            return Result(title: s, kind: .tcp, host: host, port: port, url: nil, note: note)
        }
        return nil
    }

    private static func parseBracketIPv6Port(_ s: String) -> Result? {
        guard s.hasPrefix("["), let close = s.firstIndex(of: "]") else { return nil }
        let host = String(s[s.index(after: s.startIndex)..<close])
        let rest = s[s.index(after: close)...]
        guard rest.first == ":", let port = Int(rest.dropFirst()), port > 0, port <= 65535 else {
            return nil
        }
        guard isIPv6(host) else { return nil }
        return Result(title: s, kind: .tcp, host: host, port: port, url: nil, note: "")
    }

    private static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            guard let n = Int(p), n >= 0, n <= 255, String(n) == p else { return false }
            return true
        }
    }

    private static func isTailscale(_ s: String) -> Bool {
        s.hasPrefix("100.") && isIPv4(s)
    }

    private static func isIPv6(_ s: String) -> Bool {
        var addr = in6_addr()
        return s.withCString { inet_pton(AF_INET6, $0, &addr) == 1 }
    }

    private static func isHostname(_ s: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard s.contains("."), !s.hasPrefix("."), !s.hasSuffix(".") else { return false }
        return s.count <= 253
    }

    private static func string(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        return nil
    }

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func get(_ url: URL, timeout: TimeInterval) -> Bool {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("tiny-status", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { sem.signal() }
            guard let http = response as? HTTPURLResponse else { return }
            if (200..<400).contains(http.statusCode) {
                ok = true
                return
            }
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let st = obj["status"] as? String, !st.isEmpty { ok = true }
                if let h = obj["healthy"] as? Bool, h { ok = true }
                if obj["healthy"] as? String != nil { ok = true }
            }
        }
        task.resume()
        _ = sem.wait(timeout: .now() + timeout + 1)
        if !ok { task.cancel() }
        return ok
    }
}

private extension URL {
    var originURL: URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.port = port
        return c.url ?? self
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) { return String(dropLast(suffix.count)) }
        return self
    }
}
