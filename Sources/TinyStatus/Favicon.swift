import Foundation

/// Site favicon for HTTP checks when `image` is not set.
/// Cached under `~/.config/tiny-status/favicons/`.
enum Favicon {
    private static let lock = NSLock()
    private static var failed = Set<String>()
    private static var inflight = Set<String>()

    static var directory: URL {
        ConfigLoader.userURL.deletingLastPathComponent().appendingPathComponent("favicons")
    }

    static func origin(of raw: String?) -> URL? {
        guard let raw, let u = URL(string: raw), let host = u.host, !host.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = (u.scheme == "http" || u.scheme == "https") ? u.scheme : "https"
        c.host = host
        c.port = u.port
        return c.url
    }

    static func fileKey(_ origin: URL) -> String {
        let host = (origin.host ?? "site").lowercased()
        if let p = origin.port { return "\(host)_\(p)" }
        return host
    }

    static func cached(url raw: String?) -> String? {
        guard let origin = origin(of: raw) else { return nil }
        let base = fileKey(origin)
        let fm = FileManager.default
        for ext in ["png", "ico", "jpg", "jpeg", "gif", "webp"] {
            let p = directory.appendingPathComponent("\(base).\(ext)")
            let n = (try? p.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if fm.fileExists(atPath: p.path), n > 16 { return p.path }
        }
        return nil
    }

    /// Parse `<link rel="…icon…" href="…">` (either attribute order).
    static func hrefs(in html: String, base: URL) -> [URL] {
        let pattern = #"<link\b[^>]*>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        var out: [URL] = []
        for m in re.matches(in: html, options: [], range: range) {
            let tag = ns.substring(with: m.range)
            let low = tag.lowercased()
            guard low.contains("rel=") else { continue }
            let rel = (attr(low, "rel") ?? "").lowercased()
            guard rel.contains("icon") else { continue }
            guard let href = attr(tag, "href"), !href.isEmpty else { continue }
            if href.lowercased().hasPrefix("data:") { continue }
            if href.lowercased().contains(".svg") { continue }
            if let u = URL(string: href, relativeTo: base)?.absoluteURL { out.append(u) }
        }
        return out
    }

    static func fetch(url raw: String?) -> String? {
        if let hit = cached(url: raw) { return hit }
        guard let origin = origin(of: raw) else { return nil }
        let key = fileKey(origin)
        lock.lock()
        if failed.contains(key) || inflight.contains(key) {
            lock.unlock()
            return cached(url: raw)
        }
        inflight.insert(key)
        lock.unlock()
        defer {
            lock.lock()
            inflight.remove(key)
            lock.unlock()
        }
        var candidates = hrefs(in: getText(origin), base: origin)
        candidates.append(origin.appendingPathComponent("favicon.ico"))
        candidates.append(origin.appendingPathComponent("favicon.png"))
        var seen = Set<String>()
        for u in candidates {
            let s = u.absoluteString
            if !seen.insert(s).inserted { continue }
            if s.contains(".svg") { continue }
            if let path = save(data: getData(u), origin: origin, hint: u) { return path }
        }
        lock.lock()
        failed.insert(key)
        lock.unlock()
        return nil
    }

    private static func attr(_ tag: String, _ name: String) -> String? {
        let p = #"\#(name)\s*=\s*["']([^"']+)["']"#
        guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let m = re.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func getText(_ url: URL) -> String {
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.setValue("text/html,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var text = ""
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data { text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 7)
        return text
    }

    private static func getData(_ url: URL) -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.setValue("image/*,*/*;q=0.5", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        var code: Int?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            code = (resp as? HTTPURLResponse)?.statusCode
            out = data
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 7)
        guard let code, (200..<300).contains(code), let out, out.count > 16 else { return nil }
        return out
    }

    private static func save(data: Data?, origin: URL, hint: URL) -> String? {
        guard let data, data.count > 16 else { return nil }
        let ext = extFor(data: data, hint: hint)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent("\(fileKey(origin)).\(ext)")
        do {
            try data.write(to: dest, options: .atomic)
            return dest.path
        } catch {
            return nil
        }
    }

    static func extFor(data: Data, hint: URL) -> String {
        let b = [UInt8](data.prefix(12))
        if b.count >= 8, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "png" }
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "jpg" }
        if b.count >= 6, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "gif" }
        if b.count >= 4, b[0] == 0x00, b[1] == 0x00, b[2] == 0x01, b[3] == 0x00 { return "ico" }
        if b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,
           b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return "webp" }
        let path = hint.path.lowercased()
        for e in ["png", "ico", "jpg", "jpeg", "gif", "webp"] where path.hasSuffix(".\(e)") {
            return e == "jpeg" ? "jpg" : e
        }
        return "ico"
    }
}
