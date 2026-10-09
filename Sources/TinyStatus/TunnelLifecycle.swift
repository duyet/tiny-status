import Foundation

enum TunnelState: Equatable {
    case stopped
    case starting(attempt: Int, max: Int)
    case connected(since: Date)
    case failed(exitCode: Int32, stderr: String)
}

/// Start / stop / retry for tunnel checks. Start launches the start argv (often long-lived, e.g. `ssh -N`),
/// then polls a TCP connect to the check's port with backoff.
@MainActor
final class TunnelLifecycle {
    static let shared = TunnelLifecycle()
    static let didChange = Notification.Name("TunnelLifecycleDidChange")
    nonisolated static let maxAttempts = 10

    private(set) var states: [String: TunnelState] = [:]
    private var procs: [String: Process] = [:]
    private var tokens: [String: UUID] = [:]

    func state(for id: String) -> TunnelState { states[id] ?? .stopped }

    func start(_ check: Check) {
        guard let argv = Self.command(check, "start"), let port = check.port else {
            set(check.id, .failed(exitCode: 127, stderr: "no start action or port"))
            return
        }
        let host = check.host ?? "127.0.0.1"
        let token = UUID()
        tokens[check.id] = token
        procs[check.id]?.terminate()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch {
            set(check.id, .failed(exitCode: 127, stderr: Self.tail("\(error)")))
            return
        }
        procs[check.id] = p
        set(check.id, .starting(attempt: 1, max: Self.maxAttempts))

        let id = check.id
        Task.detached {
            for attempt in 1 ... Self.maxAttempts {
                if !p.isRunning, p.terminationStatus != 0 {
                    let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    await self.finish(id, token, .failed(exitCode: p.terminationStatus, stderr: Self.tail(msg)))
                    return
                }
                await self.finish(id, token, .starting(attempt: attempt, max: Self.maxAttempts))
                if TCP.canConnect(host: host, port: port) {
                    await self.finish(id, token, .connected(since: Date()))
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(Self.backoff(attempt) * 1_000_000_000))
            }
            let code: Int32 = p.isRunning ? 124 : p.terminationStatus
            await self.finish(id, token, .failed(exitCode: code, stderr: "port \(port) not reachable after \(Self.maxAttempts) attempts"))
        }
    }

    func stop(_ check: Check) {
        tokens[check.id] = nil
        procs.removeValue(forKey: check.id)?.terminate()
        if let argv = Self.command(check, "stop") {
            Task.detached { _ = Shell.run(argv, timeout: 30) }
        }
        set(check.id, .stopped)
    }

    func retry(_ check: Check) {
        stop(check)
        start(check)
    }

    func statusText(for id: String, now: Date = Date()) -> String {
        Self.text(state(for: id), port: Store.shared.allChecks().first { $0.id == id }?.port, now: now)
    }

    nonisolated static func text(_ s: TunnelState, port: Int?, now: Date = Date()) -> String {
        switch s {
        case .stopped:
            return "Stopped"
        case let .starting(attempt, max):
            return "Starting · waiting for port \(port.map(String.init) ?? "?") (attempt \(attempt)/\(max))"
        case let .connected(since):
            return "Connected · up \(uptime(now.timeIntervalSince(since)))"
        case let .failed(code, stderr):
            return stderr.isEmpty ? "Failed · exit \(code)" : "Failed · exit \(code): \(stderr)"
        }
    }

    nonisolated static func uptime(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    /// Seconds before the next connect attempt: 0.5, 1, 2, 4, capped at 5.
    nonisolated static func backoff(_ attempt: Int) -> Double {
        min(5, 0.5 * pow(2, Double(attempt - 1)))
    }

    nonisolated static func tail(_ s: String, _ n: Int = 300) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > n ? "…" + t.suffix(n) : t
    }

    nonisolated private static func command(_ check: Check, _ action: String) -> [String]? {
        guard let cmd = check.resolvedActions().first(where: { $0.id == action })?.command, !cmd.isEmpty else { return nil }
        return cmd
    }

    private func finish(_ id: String, _ token: UUID, _ s: TunnelState) {
        guard tokens[id] == token else { return }
        if case .failed = s { procs.removeValue(forKey: id)?.terminate() }
        set(id, s)
    }

    private func set(_ id: String, _ s: TunnelState) {
        guard states[id] != s else { return }
        states[id] = s
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["id": id])
    }
}
