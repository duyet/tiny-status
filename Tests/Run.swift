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
        custom.actions = [CheckAction(id: "reboot", title: "Reboot", command: ["/usr/bin/true"], when: "always")]
        expect(custom.resolvedActions().map(\.id) == ["reboot"], "custom actions win over empty legacy")

        expect(Check(id: "a", title: "A", kind: .http).isEnabled, "enabled by default")
        var off = Check(id: "a", title: "A", kind: .http)
        off.enabled = false
        expect(!off.isEnabled, "enabled false")

        expect(HTTP.isHealthy(json: nil, code: 200), "2xx healthy")
        expect(!HTTP.isHealthy(json: nil, code: 404), "404 down")
        expect(HTTP.isHealthy(json: ["status": "ok"], code: 200), "status ok")
        expect(!HTTP.isHealthy(json: ["status": "unhealthy"], code: 200), "json unhealthy wins")
        expect(HTTP.isHealthy(json: ["healthy": true], code: 200), "healthy bool")

        let origin = Check(id: "web", title: "Web", kind: .http, url: "https://example.com")
        expect(HealthDiscover.wantsDiscover(origin), "origin wants discover")
        expect(HealthDiscover.needsConfigure(origin), "origin needs configure")
        var specific = Check(id: "web", title: "Web", kind: .http, url: "https://example.com/health")
        specific.discover = false
        expect(!HealthDiscover.wantsDiscover(specific), "explicit path no discover")
        expect(HealthDiscover.stableId(host: "AnyRouter.dev", url: nil, title: "x") == "anyrouter.dev", "stable id")

        let paths = HealthDiscover.paths(check: origin, config: ["/ready", "live"])
        expect(paths == ["/ready", "/live"], "discoverPaths slash")

        let parsed = Discovery.parse("https://example.com\n127.0.0.1:6379")
        expect(parsed.contains { $0.kind == .http && $0.host == "example.com" }, "parse https")
        expect(parsed.contains { $0.kind == .tcp && $0.port == 6379 }, "parse host:port")
        expect(parsed.first { $0.kind == .http }?.discover == true, "https paste discovers")

        let id = Discovery.Result(
            title: "example.com", kind: .http, host: "example.com", port: nil,
            url: "https://example.com", note: "", discover: true
        ).asCheck().id
        expect(id == "example.com", "asCheck stable id")

        let tags = Tags.inferred(title: "EU prod", kind: .http)
        expect(tags.contains("EU") && tags.contains("prod"), "infer tags")

        if failed > 0 {
            fputs("\(failed) failed\n", stderr)
            exit(1)
        }
        print("ok")
    }
}
