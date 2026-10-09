import AppKit
import Foundation

@main
enum TinyStatusTests {
    static func main() {
        var failed = 0
        func expect(_ cond: Bool, _ msg: String) {
            if !cond {
                fputs("FAIL \(msg)\n", stderr)
                failed += 1
            }
        }

        // resolvedActions maps legacy start/stop
        var tunnel = Check(id: "ssh", title: "Tunnel", kind: .tcp, host: "127.0.0.1", port: 8443)
        tunnel.start = ["/usr/bin/true", "start", "--no-open"]
        tunnel.stop = ["/usr/bin/true", "stop"]
        tunnel.open = ["/usr/bin/true", "open"]
        let acts = tunnel.resolvedActions()
        expect(acts.map(\.id) == ["start", "stop", "open"], "legacy action ids")
        expect(acts.first { $0.id == "start" }?.title == "Connect", "start title Connect")
        expect(acts.first { $0.id == "stop" }?.title == "Disconnect", "stop title Disconnect")
        expect(acts.first { $0.id == "start" }?.isVisible(up: false) == true, "connect when down")
        expect(acts.first { $0.id == "start" }?.isVisible(up: true) == false, "connect hidden when up")
        expect(acts.first { $0.id == "stop" }?.isVisible(up: true) == true, "disconnect when up")

        var custom = Check(id: "x", title: "X", kind: .tcp)
        custom.start = ["/usr/bin/true"]
        custom.actions = [CheckAction(id: "reboot", title: "Reboot", command: ["/usr/bin/true"], when: "always")]
        expect(custom.resolvedActions().map(\.id) == ["reboot"], "custom actions win over legacy start")
        expect(CheckAction(id: "x", title: "X", when: nil).isVisible(up: true), "always visible when up")
        expect(CheckAction(id: "x", title: "X", when: nil).isVisible(up: false), "always visible when down")
        expect(CheckAction(id: "x", title: "X", when: "up").isVisible(up: true), "up-only when up")
        expect(!CheckAction(id: "x", title: "X", when: "up").isVisible(up: false), "up-only hidden when down")
        expect(!CheckAction(id: "x", title: "X", when: "down").isVisible(up: true), "down-only hidden when up")

        expect(Check(id: "a", title: "A", kind: .http).isEnabled, "enabled by default")
        expect(Check(id: "a", title: "A", kind: .http).wantsAlert, "alert by default")
        var mute = Check(id: "a", title: "A", kind: .http)
        mute.alert = .flag(false)
        expect(!mute.wantsAlert, "alert false")
        mute.alert = .rule(Alerts(after: 5))
        expect(mute.wantsAlert, "alert object keeps alerts on")
        var off = Check(id: "a", title: "A", kind: .http)
        off.enabled = false
        expect(!off.isEnabled, "enabled false")

        // Alerts: debounce flaps, alert once per outage, recover only after a sent alert.
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let rule = AlertRule.resolve(nil, nil)
        expect(rule == AlertRule(), "alert defaults: on, after 2, recover, no repeat, sound")
        var st = AlertState()
        var ev: AlertEvent?
        (st, ev) = AlertLogic.step(st, down: true, rule: rule, now: t0)
        expect(ev == nil, "one failed poll is a flap, no alert")
        (st, ev) = AlertLogic.step(st, down: false, rule: rule, now: t0)
        expect(ev == nil && st == AlertState(), "flap recovery is silent and resets")
        (st, _) = AlertLogic.step(st, down: true, rule: rule, now: t0)
        (st, ev) = AlertLogic.step(st, down: true, rule: rule, now: t0)
        expect(ev == .down, "after 2 fails alerts down")
        (st, ev) = AlertLogic.step(st, down: true, rule: rule, now: t0.addingTimeInterval(9999))
        expect(ev == nil, "repeat 0 never re-alerts")
        (st, ev) = AlertLogic.step(st, down: false, rule: rule, now: t0)
        expect(ev == .recovered, "recovers after a sent down alert")

        var rep = rule
        rep.repeat = 1800
        st = AlertState(fails: 2, alerted: true, lastAlertAt: t0)
        (st, ev) = AlertLogic.step(st, down: true, rule: rep, now: t0.addingTimeInterval(600))
        expect(ev == nil, "no repeat before window")
        (st, ev) = AlertLogic.step(st, down: true, rule: rep, now: t0.addingTimeInterval(1800))
        expect(ev == .down && st.lastAlertAt == t0.addingTimeInterval(1800), "repeat after window")

        var noRecover = rule
        noRecover.recover = false
        expect(AlertLogic.step(st, down: false, rule: noRecover, now: t0).1 == nil, "recover false is silent")

        (st, ev) = AlertLogic.step(AlertState(), down: true, rule: rule, now: t0, baseline: true)
        expect(ev == nil && !st.alerted, "first poll after launch never alerts")
        expect(AlertLogic.step(st, down: false, rule: rule, now: t0).1 == nil, "no recovery for an unsent baseline alert")
        (st, ev) = AlertLogic.step(st, down: true, rule: rule, now: t0)
        expect(ev == .down, "down at launch alerts once debounce is met")

        var ruleOff = rule
        ruleOff.enabled = false
        expect(AlertLogic.step(AlertState(fails: 5), down: true, rule: ruleOff, now: t0).1 == nil, "disabled never alerts")

        let quiet = QuietHours("22:00-08:00")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let at = { (h: Int, m: Int) in cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: h, minute: m))! }
        expect(quiet?.contains(at(23, 0), calendar: cal) == true, "quiet wraps midnight (late)")
        expect(quiet?.contains(at(7, 59), calendar: cal) == true, "quiet wraps midnight (early)")
        expect(quiet?.contains(at(8, 0), calendar: cal) == false, "quiet end is exclusive")
        expect(QuietHours("12:00-13:00")?.contains(at(12, 30), calendar: cal) == true, "quiet same-day window")
        expect(QuietHours("25:00-08:00") == nil && QuietHours("nope") == nil, "bad quiet rejected")
        var q = rule
        q.quiet = quiet
        expect(!q.audible(at: at(23, 0), calendar: cal), "quiet hours mute sound")
        expect(q.audible(at: at(12, 0), calendar: cal), "sound outside quiet hours")

        let ev3: [(id: String, title: String, event: AlertEvent, sound: Bool, tunnel: Bool)] = [
            ("a", "A", .down, true, false), ("b", "B", .down, false, false), ("c", "C", .down, false, false),
            ("d", "D", .recovered, false, false),
        ]
        let grouped = AlertLogic.notes(ev3)
        expect(grouped.count == 2 && grouped[0].title == "3 checks down" && grouped[0].body == "A, B, C", "3 downs group into one")
        expect(grouped[0].sound, "group plays sound if any member would")
        expect(grouped[1].body == "Recovered", "recoveries stay separate")
        let two = AlertLogic.notes(Array(ev3.prefix(2)))
        expect(two.map(\.id) == ["a", "b"] && two[0].thread == "a", "2 downs notify per check")
        expect(AlertLogic.notes([("t", "T", .down, true, true)])[0].category == AlertCenter.tunnelCategory, "tunnel category")

        let global = try? JSONDecoder().decode(
            Alerts.self, from: Data(#"{"after":3,"repeat":600,"quiet":"22:00-08:00","sound":false}"#.utf8)
        )
        let per = try? JSONDecoder().decode(Check.self, from: Data(#"{"id":"x","title":"X","kind":"tcp","alert":{"after":5,"repeat":0}}"#.utf8))
        let merged = AlertRule.resolve(global, per?.alert)
        expect(merged.after == 5 && merged.repeat == 0 && !merged.sound && merged.quiet != nil, "per-check object merges over global")
        let flagOff = try? JSONDecoder().decode(Check.self, from: Data(#"{"id":"x","title":"X","kind":"tcp","alert":false}"#.utf8))
        expect(flagOff?.alert == .flag(false) && !AlertRule.resolve(global, flagOff?.alert).enabled, "alert false parses and mutes")
        expect(!AlertRule.resolve(Alerts(enabled: false), per?.alert).enabled, "global enabled false is a master switch")
        let encoded = (try? JSONEncoder().encode(flagOff?.alert)).flatMap { String(data: $0, encoding: .utf8) }
        expect(encoded == "false", "alert false round-trips as bool")

        expect(TableDensity.rowSize(false) == .large, "relaxed uses large rows")
        expect(TableDensity.rowSize(true) == .small, "compact uses small rows")
        expect(TableDensity.indent(false) == 22, "relaxed indent")
        expect(TableDensity.spacing(false).height == 6, "relaxed row gap")
        expect(TableDensity.icon(false) == 22, "relaxed icon")
        expect(TableDensity.statusColumn(false) == 44, "relaxed status column")
        expect(TableDensity.indent(true) == 11, "compact indent")
        expect(TableDensity.icon(true) == 16, "compact icon")
        expect(TableDensity.historyHeight(false) == 18, "relaxed history height")
        expect(TableDensity.historySlots(true) == 24, "compact history slots")
        expect(CheckArt.symbol(icon: nil, kind: .tcp, enabled: true) == "network", "tcp default symbol")
        expect(CheckArt.symbol(icon: nil, kind: .http, enabled: true) == "globe", "http default symbol")
        expect(CheckArt.symbol(icon: nil, kind: .command, enabled: true) == "terminal", "command default symbol")
        expect(CheckArt.symbol(icon: "lock.shield", kind: .tcp, enabled: true) == "lock.shield", "explicit icon wins")
        expect(CheckArt.symbol(icon: "globe", kind: .http, enabled: false) == "pause.circle", "disabled uses pause")

        expect(HTTP.isHealthy(json: nil, code: 200), "2xx healthy")
        expect(!HTTP.isHealthy(json: nil, code: 404), "404 down")
        expect(HTTP.isHealthy(json: ["status": "ok"], code: 200), "status ok")
        expect(!HTTP.isHealthy(json: ["status": "unhealthy"], code: 200), "json unhealthy wins")
        expect(HTTP.isHealthy(json: ["healthy": true], code: 200), "healthy bool")
        expect(!HTTP.isHealthy(json: ["healthy": false], code: 200), "healthy false is down")
        expect(HTTP.isHealthy(json: ["status": "PASS"], code: 503), "ok status beats non-2xx")
        expect(!HTTP.isHealthy(json: ["status": "error"], code: 200), "error status is down")
        expect(!HTTP.isHealthy(json: nil, code: 302), "3xx is not healthy")
        expect(HTTP.isHealthy(json: nil, code: 201), "201 is 2xx")
        expect(!HTTP.isHealthy(json: nil, code: nil), "no code is down")
        expect(Probe.tag("ghcr.io/example/app:1.2.3") == "1.2.3", "k8s tag after colon")
        expect(Probe.tag("   ") == "—", "empty image tag")
        expect(Probe.tag("sha256abc") == "sha256abc", "untagged image")
        expect(DeployRow.healthScore("healthy") == 1, "healthy score")
        expect(DeployRow.healthScore("degraded") == 0.5, "degraded score")
        expect(DeployRow.healthScore("down") == 0, "down score")

        let origin = Check(id: "web", title: "Web", kind: .http, url: "https://example.com")
        expect(HealthDiscover.wantsDiscover(origin), "origin wants discover")
        expect(HealthDiscover.needsConfigure(origin), "origin needs configure")
        var specific = Check(id: "web", title: "Web", kind: .http, url: "https://example.com/health")
        specific.discover = false
        expect(!HealthDiscover.wantsDiscover(specific), "explicit path no discover")
        expect(HealthDiscover.stableId(host: "www.example.com", url: nil, title: "x") == "example.com", "stable id strips www")
        expect(HealthDiscover.stableId(host: nil, url: "https://example.com/a", title: "x") == "example.com", "stable id from url")
        expect(HealthDiscover.pingEnabled(origin), "ping on by default")
        var noping = origin
        noping.ping = false
        expect(!HealthDiscover.pingEnabled(noping), "ping false skips tcp fallback")
        expect(HealthDiscover.defaultPaths.contains("/api/v1/healthz"), "default healthz path")
        expect(!HealthDiscover.wantsDiscover(Check(id: "c", title: "C", kind: .command, command: ["/usr/bin/true"])), "command does not discover")

        let paths = HealthDiscover.paths(check: origin, config: ["/ready", "live"])
        expect(paths == ["/ready", "/live"], "discoverPaths slash")

        let parsed = Discovery.parse("https://example.com\n127.0.0.1:6379")
        expect(parsed.contains { $0.kind == .http && $0.host == "example.com" }, "parse https")
        expect(parsed.contains { $0.kind == .tcp && $0.port == 6379 }, "parse host:port")
        expect(parsed.first { $0.kind == .http }?.discover == true, "https paste discovers")
        expect(Discovery.parse("").isEmpty, "empty paste")
        expect(Discovery.parse("   \n  ").isEmpty, "whitespace paste")
        let hp = Discovery.parse("localhost:8443")
        expect(hp.count == 1 && hp[0].kind == .tcp && hp[0].port == 8443, "localhost:port")
        let v6 = Discovery.parse("[::1]:6379")
        expect(v6.first?.kind == .tcp && v6.first?.host == "::1" && v6.first?.port == 6379, "bracket ipv6 port")
        expect(Discovery.parse("127.0.0.1:99999").isEmpty, "port out of range")
        let bareIP = Discovery.parse("127.0.0.1")
        expect(bareIP.map(\.port) == [443, 80], "bare ipv4 tries 443 then 80")
        let ts = Discovery.parse("100.64.0.1")
        expect(ts.map(\.port) == [22, 443], "100.x looks like tailscale")
        let hostPaste = Discovery.parse("example.com")
        expect(hostPaste.contains { $0.kind == .http && $0.discover == true }, "hostname infers https discover")
        expect(hostPaste.contains { $0.kind == .tcp && $0.port == 443 }, "hostname also offers tcp 443")
        let jsonOne = Discovery.parse(#"{"url":"https://example.com/health","title":"Web"}"#)
        expect(jsonOne.first?.kind == .http && jsonOne.first?.title == "Web", "json url object")
        let jsonArr = Discovery.parse(#"[{"host":"127.0.0.1","port":6379},{"command":["/usr/bin/true"]}]"#)
        expect(jsonArr.contains { $0.kind == .tcp && $0.port == 6379 }, "json array tcp")
        expect(jsonArr.contains { $0.kind == .command }, "json array command")
        let jsonChecks = Discovery.parse(#"{"checks":[{"url":"https://example.com"}]}"#)
        expect(jsonChecks.isEmpty, "Discovery.parse does not unwrap checks[]; CLI add does")
        let jsonCmd = Discovery.parse(#"{"command":"/usr/bin/true --ok"}"#)
        expect(jsonCmd.first?.kind == .command, "command string splits")

        let id = Discovery.Result(
            title: "example.com", kind: .http, host: "example.com", port: nil,
            url: "https://example.com", note: "", discover: true
        ).asCheck().id
        expect(id == "example.com", "asCheck stable id")

        let tags = Tags.inferred(title: "EU prod", kind: .http)
        expect(tags.contains("EU") && tags.contains("prod"), "infer tags")
        expect(TagTint.slot("prod") == .red, "prod tag red")
        expect(TagTint.slot("dev") == .green, "dev tag green")
        expect(TagTint.slot("Tunnel") == .blue, "tunnel tag blue")
        expect(TagTint.slot("EU") == .blue, "EU tag blue")
        expect(TagTint.slot("alpha") == TagTint.slot("alpha"), "same tag same color")

        expect(Favicon.origin(of: "https://example.com/health")?.host == "example.com", "favicon origin host")
        expect(Favicon.origin(of: "https://example.com:8443/a")?.port == 8443, "favicon origin port")
        expect(Favicon.origin(of: "not a url") == nil, "favicon rejects junk")
        expect(Favicon.fileKey(URL(string: "https://Example.COM")!) == "example.com", "favicon key lower")
        let html = #"<head><link rel="shortcut icon" href="/fav.png"><link href="/x.ico" rel="icon"></head>"#
        let hrefs = Favicon.hrefs(in: html, base: URL(string: "https://example.com")!)
        expect(hrefs.map(\.absoluteString) == ["https://example.com/fav.png", "https://example.com/x.ico"], "favicon html links")
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0, count: 8))
        expect(Favicon.extFor(data: png, hint: URL(string: "https://example.com/x.ico")!) == "png", "png magic wins")
        let jpeg = Data([0xFF, 0xD8, 0xFF] + [UInt8](repeating: 0, count: 16))
        expect(Favicon.extFor(data: jpeg, hint: URL(string: "https://example.com/a")!) == "jpg", "jpeg magic")
        expect(Favicon.extFor(data: Data(repeating: 0, count: 20), hint: URL(string: "https://example.com/x.webp")!) == "webp", "hint extension")
        expect(Favicon.extFor(data: Data([1, 2, 3, 4]), hint: URL(string: "https://example.com/noext")!) == "ico", "fallback ico")
        expect(Vars.apply("https://{host}/a", ["host": "example.com"]) == "https://example.com/a", "vars replace")
        expect(Vars.apply("{home}/bin", ["home": "/Users/me"]) == "/Users/me/bin", "vars home")
        let nested = Vars.table(["host": "example.com", "health": "https://{host}/health"])
        expect(nested["health"] == "https://example.com/health", "custom vars nest")
        expect(Vars.apply("x{missing}y", [:]) == "x{missing}y", "unknown token stays")
        if ProcessInfo.processInfo.environment["PATH"] != nil {
            let expanded = Vars.apply("p={env:PATH}", [:])
            expect(!expanded.contains("{env:PATH}"), "env token expands")
        }

        let t = Tunnel(id: "ssh", title: "Tunnel", start: ["/usr/bin/true"], probePort: 8443)
        let fromT = Check.from(tunnel: t)
        expect(fromT.kind == .tcp && fromT.host == "127.0.0.1" && fromT.port == 8443, "tunnel maps to tcp localhost")
        let d = Deployment(id: "web", title: "Web", healthUrl: "https://example.com/health", openUrl: "https://example.com")
        let fromD = Check.from(deployment: d)
        expect(fromD.kind == .http && fromD.url == "https://example.com/health", "deployment maps to http")

        var tagged = Check(id: "w", title: "Web", kind: .http)
        tagged.tags = ["homelab", " "]
        tagged.group = "  Labs "
        expect(Tags.resolved(tagged) == ["homelab"], "explicit tags trim empty")
        expect(Tags.group(tagged) == "Labs", "explicit group wins")
        expect(Tags.group(Check(id: "t", title: "Tunnel", kind: .tcp)) == "Tunnel", "tcp infers Tunnel group")
        expect(Tags.inferred(title: "db", kind: .http) == ["Other"], "unknown title is Other")

        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "checks.example.json")),
           let cfg = try? decoder.decode(Config.self, from: data)
        {
            expect(cfg.checks?.contains { $0.id == "web" && $0.kind == .http } == true, "example has http web")
            expect(cfg.checks?.contains { $0.id == "paused" && $0.isEnabled == false } == true, "example paused disabled")
            expect(cfg.checks?.contains { $0.id == "cmd" && $0.kind == .command } == true, "example command")
            expect(cfg.vars?["host"] == "example.com", "example vars generic")
        } else {
            expect(false, "decode checks.example.json")
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "tunnels.example.json")),
           let cfg = try? decoder.decode(Config.self, from: data)
        {
            expect(!(cfg.checks ?? []).isEmpty, "tunnels.example has checks")
        } else {
            expect(false, "decode tunnels.example.json")
        }

        let round = Check(id: "web", title: "Web", kind: .http, url: "https://example.com/health", discover: false)
        if let encoded = try? JSONEncoder().encode(round),
           let back = try? decoder.decode(Check.self, from: encoded)
        {
            expect(back.id == "web" && back.kind == .http && back.discover == false, "check json roundtrip")
        } else {
            expect(false, "check json roundtrip encode")
        }

        let tsUp = TailscaleStatus.parse([
            "BackendState": "Running",
            "Self": ["HostName": "my-machine", "Online": true],
        ])
        expect(tsUp.up && tsUp.detail == "my-machine", "tailscale running uses hostname")
        expect(TailscaleStatus.parse(["BackendState": "Stopped"]).detail == "Stopped", "tailscale stopped")
        expect(TailscaleStatus.parse(["BackendState": "NeedsLogin"]).detail == "Needs login", "tailscale needs login")
        expect(!TailSnap.missing.installed, "missing tailscale")
        expect(!NetSnap.offline.online && NetSnap.offline.title == "Offline", "offline snap")

        // New Tunnel sheet: argv is built as separate args, never a shell string
        let tin = TunnelSpec.Input(name: "Web Tunnel", localPort: "8443", remote: "127.0.0.1:443", via: "my-machine.tailnet.ts.net")
        expect(TunnelSpec.validate(tin) == nil, "valid tunnel input")
        let tc = TunnelSpec.check(tin)
        expect(tc?.id == "web-tunnel" && tc?.kind == .tcp, "tunnel id and kind")
        expect(tc?.host == "127.0.0.1" && tc?.port == 8443, "tunnel probes local port")
        expect(tc?.tags == ["tunnel"], "tunnel tag")
        expect(
            tc?.resolvedActions().first { $0.id == "start" }?.command
                == ["/usr/bin/ssh", "-N", "-L", "8443:127.0.0.1:443", "my-machine.tailnet.ts.net"],
            "tunnel start argv"
        )
        expect(
            tc?.resolvedActions().first { $0.id == "stop" }?.command == ["/usr/bin/pkill", "-f", "8443:127.0.0.1:443"],
            "tunnel stop argv matches the forward spec"
        )
        func badTunnel(_ edit: (inout TunnelSpec.Input) -> Void) -> Bool {
            var i = tin
            edit(&i)
            return TunnelSpec.validate(i) != nil && TunnelSpec.check(i) == nil
        }
        expect(badTunnel { $0.name = " " }, "tunnel needs name")
        expect(badTunnel { $0.localPort = "0" }, "local port 0 rejected")
        expect(badTunnel { $0.localPort = "65536" }, "local port over 65535 rejected")
        expect(badTunnel { $0.localPort = "80a" }, "local port non-numeric rejected")
        expect(badTunnel { $0.localPort = "-1" }, "local port negative rejected")
        expect(badTunnel { $0.remote = "example.com" }, "remote needs port")
        expect(badTunnel { $0.remote = ":443" }, "remote needs host")
        expect(badTunnel { $0.remote = "example.com:99999" }, "remote port range")
        expect(badTunnel { $0.via = "" }, "via required")
        expect(badTunnel { $0.via = "-oProxyCommand=x" }, "via cannot be an ssh option")
        expect(badTunnel { $0.via = "a b" }, "via no spaces")
        expect(TunnelSpec.port("65535") == 65535 && TunnelSpec.port("1") == 1, "port bounds inclusive")

        // Tunnel lifecycle status text
        expect(TunnelLifecycle.text(.starting(attempt: 2, max: 10), port: 2222) == "Starting · waiting for port 2222 (attempt 2/10)", "starting text")
        let now = Date()
        expect(TunnelLifecycle.text(.connected(since: now.addingTimeInterval(-(2 * 3600 + 14 * 60))), port: 1, now: now) == "Connected · up 2h 14m", "connected text")
        expect(TunnelLifecycle.text(.failed(exitCode: 255, stderr: "refused"), port: 1) == "Failed · exit 255: refused", "failed text")
        expect(TunnelLifecycle.tail(String(repeating: "x", count: 500)).count == 301, "stderr tail capped at 300")
        expect(TunnelLifecycle.backoff(1) == 0.5 && TunnelLifecycle.backoff(10) == 5, "backoff grows and caps")

        // Sidebar buckets: a TCP check with a start action is a tunnel; filters must not leak other kinds.
        var tun = Check(id: "t", title: "T", kind: .tcp, host: "127.0.0.1", port: 2222)
        tun.start = ["/usr/bin/ssh", "-N", "-L", "2222:127.0.0.1:22", "my-machine.tailnet.ts.net"]
        let plainTCP = Check(id: "p", title: "P", kind: .tcp, host: "127.0.0.1", port: 6379)
        let web = Check(id: "w", title: "W", kind: .http, url: "https://example.com/health", tags: ["prod"])
        expect(SidebarScope.category(tun) == "Tunnels", "tcp with start is a tunnel")
        expect(SidebarScope.category(plainTCP) == "TCP", "plain tcp stays TCP")
        var taggedTCP = plainTCP
        taggedTCP.tags = ["tunnel"]
        expect(SidebarScope.category(taggedTCP) == "Tunnels", "explicit tunnel tag is a tunnel")
        expect(SidebarScope.category(Check(id: "c", title: "C", kind: .command)) == "Commands", "command bucket")
        expect(SidebarScope.kind("HTTP").matches(web, attention: false), "kind HTTP matches http")
        expect(!SidebarScope.kind("Tunnels").matches(plainTCP, attention: false), "tunnels excludes plain tcp")
        expect(SidebarScope.tag("prod").matches(web, attention: false), "tag scope matches")
        expect(!SidebarScope.tag("prod").matches(plainTCP, attention: false), "tag scope excludes untagged")
        expect(!SidebarScope.attention.matches(web, attention: false), "attention hides healthy")
        expect(SidebarScope.attention.matches(web, attention: true), "attention shows down")

        // Inspector stats over retained history.
        expect(Stats.median([30, 10, 20]) == 20, "median odd")
        expect(Stats.median([10, 20, 30, 40]) == 25, "median even")
        expect(Stats.median([]) == nil, "median empty")
        expect(Stats.uptime([1, 1, 0, 0.5]) == 0.625, "uptime counts degraded as half")
        expect(Stats.uptime([]) == nil, "uptime empty")

        if failed > 0 {
            fputs("\(failed) failed\n", stderr)
            exit(1)
        }
        print("ok")
    }
}
