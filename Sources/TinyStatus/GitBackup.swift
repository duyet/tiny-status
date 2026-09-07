import Foundation

enum GitBackup {
    enum Op { case backup, pull, sync, keepLocal, keepRemote }

    struct Spec {
        var repo: String
        var file: String
        var remote: String
        var branch: String
        var remoteUrl: String?
        var localConfig: URL
    }

    static func run(_ op: Op, _ spec: Spec) -> (Bool, String, Bool) {
        var log: [String] = []
        func git(_ args: [String], timeout: TimeInterval = 90) -> (Int32, String) {
            Shell.capture(["/usr/bin/git", "-C", spec.repo] + args, timeout: timeout)
        }
        if !FileManager.default.fileExists(atPath: spec.repo) {
            if let url = spec.remoteUrl, !url.isEmpty {
                let (c, o) = Shell.capture(
                    ["/usr/bin/git", "clone", "--branch", spec.branch, url, spec.repo],
                    timeout: 120
                )
                log.append(o)
                if c != 0 { return (false, log.joined(separator: "\n"), false) }
            } else {
                return (false, "Repo folder missing: \(spec.repo)\nClone it first, or set remoteUrl.", false)
            }
        }
        let dest = URL(fileURLWithPath: spec.repo).appendingPathComponent(spec.file)
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        switch op {
        case .backup, .sync:
            if op == .sync {
                let (c, o) = git(["fetch", spec.remote, spec.branch])
                log.append(o)
                let (c2, o2) = git(["pull", "--rebase", "--autostash", spec.remote, spec.branch])
                log.append(o2)
                if c != 0 || c2 != 0 {
                    let conflict = o2.contains("CONFLICT") || o2.contains("conflict")
                    return (false, log.joined(separator: "\n"), conflict)
                }
            }
            if let data = try? Data(contentsOf: spec.localConfig) {
                try? data.write(to: dest, options: .atomic)
            }
            _ = git(["add", spec.file])
            let (cc, co) = git(["commit", "-m", "backup: tiny-status config"])
            log.append(co)
            if cc != 0, !co.contains("nothing to commit") {
                // still try push if only "nothing to commit"
            }
            let (cp, po) = git(["push", spec.remote, spec.branch])
            log.append(po)
            if cp != 0 {
                let gh = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/gh")
                    ? "/opt/homebrew/bin/gh" : "/usr/local/bin/gh"
                let (cg, go) = Shell.capture([gh, "repo", "sync"], timeout: 90, cwd: spec.repo)
                log.append(go)
                if cg != 0 { return (false, log.joined(separator: "\n"), false) }
            }
            return (true, log.joined(separator: "\n"), false)

        case .pull:
            let (c, o) = git(["pull", "--rebase", "--autostash", spec.remote, spec.branch])
            log.append(o)
            if c != 0 {
                return (false, log.joined(separator: "\n"), o.contains("CONFLICT") || o.contains("conflict"))
            }
            if FileManager.default.fileExists(atPath: dest.path),
               let data = try? Data(contentsOf: dest)
            {
                try? data.write(to: spec.localConfig, options: .atomic)
                log.append("Restored \(spec.localConfig.path)")
            }
            return (true, log.joined(separator: "\n"), false)

        case .keepLocal:
            _ = git(["rebase", "--abort"])
            _ = git(["merge", "--abort"])
            if let data = try? Data(contentsOf: spec.localConfig) {
                try? data.write(to: dest, options: .atomic)
            }
            _ = git(["add", spec.file])
            log.append(git(["commit", "-m", "backup: keep local config"]).1)
            log.append(git(["push", spec.remote, spec.branch]).1)
            return (true, log.joined(separator: "\n"), false)

        case .keepRemote:
            _ = git(["rebase", "--abort"])
            _ = git(["merge", "--abort"])
            log.append(git(["pull", spec.remote, spec.branch]).1)
            if FileManager.default.fileExists(atPath: dest.path),
               let data = try? Data(contentsOf: dest)
            {
                try? data.write(to: spec.localConfig, options: .atomic)
                log.append("Restored remote copy")
            }
            return (true, log.joined(separator: "\n"), false)
        }
    }
}

enum Shell {
    static func run(_ args: [String], timeout: TimeInterval) -> Int32 {
        capture(args, timeout: timeout).0
    }

    static func output(_ args: [String], timeout: TimeInterval) -> String {
        guard !args.isEmpty else { return "" }
        return capture(args, timeout: timeout).1
    }

    static func capture(_ args: [String], timeout: TimeInterval, cwd: String? = nil) -> (Int32, String) {
        guard let first = args.first else { return (127, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: first)
        p.arguments = Array(args.dropFirst())
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (127, "\(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if p.isRunning {
            p.terminate()
            return (124, "timeout")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

