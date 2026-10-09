import AppKit
import Foundation
import UserNotifications

/// Global `alerts` merged with a check's `alert`, defaults filled in.
struct AlertRule: Equatable {
    var enabled = true
    var onDown = true
    var after = 2
    var recover = true
    var `repeat`: Double = 0
    var quiet: QuietHours?
    var sound = true

    /// Global `enabled: false` is a master switch; per-check fields override the rest.
    static func resolve(_ global: Alerts?, _ check: AlertSetting?) -> AlertRule {
        var r = AlertRule()
        for a in [global, check.flatMap(\.rule)].compactMap({ $0 }) {
            r.onDown = a.onDown ?? r.onDown
            r.after = max(1, a.after ?? r.after)
            r.recover = a.recover ?? r.recover
            r.repeat = a.repeat ?? r.repeat
            if let q = a.quiet { r.quiet = QuietHours(q) }
            r.sound = a.sound ?? r.sound
        }
        r.enabled = global?.enabled != false && check?.isOn != false
        return r
    }

    func audible(at now: Date, calendar: Calendar = .current) -> Bool {
        sound && quiet?.contains(now, calendar: calendar) != true
    }
}

private extension AlertSetting {
    var rule: Alerts? {
        if case let .rule(a) = self { return a }
        return nil
    }
}

/// `HH:MM-HH:MM` in local time. Wraps midnight when start > end.
struct QuietHours: Equatable {
    var start: Int
    var end: Int

    init?(_ s: String) {
        let parts = s.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let a = Self.minutes(parts[0]), let b = Self.minutes(parts[1]) else { return nil }
        start = a
        end = b
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return start <= end ? (m >= start && m < end) : (m >= start || m < end)
    }

    private static func minutes(_ s: String) -> Int? {
        let hm = s.split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2, (0 ..< 24).contains(hm[0]), (0 ..< 60).contains(hm[1]) else { return nil }
        return hm[0] * 60 + hm[1]
    }
}

struct AlertState: Equatable {
    var fails = 0
    var alerted = false
    /// Set only when a down notification was actually sent.
    var lastAlertAt: Date?
}

enum AlertEvent: Equatable {
    case down
    case recovered
}

struct AlertNote: Equatable {
    var id: String
    var title: String
    var body: String
    var thread: String
    var category: String
    var check: String?
    var sound: Bool
}

/// Pure decision logic. AlertCenter owns the state and side effects.
enum AlertLogic {
    static let groupMin = 3

    /// One poll result for one check. `baseline` = first poll after launch: track, never notify.
    static func step(_ prev: AlertState, down: Bool, rule: AlertRule, now: Date, baseline: Bool = false) -> (AlertState, AlertEvent?) {
        var s = prev
        guard down else {
            let sent = s.alerted && s.lastAlertAt != nil
            return (AlertState(), sent && rule.enabled && rule.recover ? .recovered : nil)
        }
        s.fails += 1
        if baseline { return (s, nil) }
        guard rule.enabled, rule.onDown, s.fails >= rule.after else { return (s, nil) }
        if !s.alerted {
            s.alerted = true
            s.lastAlertAt = now
            return (s, .down)
        }
        if rule.repeat > 0, let last = s.lastAlertAt, now.timeIntervalSince(last) >= rule.repeat {
            s.lastAlertAt = now
            return (s, .down)
        }
        return (s, nil)
    }

    /// Turn one poll's events into notifications. 3+ downs collapse into one.
    static func notes(_ events: [(id: String, title: String, event: AlertEvent, sound: Bool, tunnel: Bool)]) -> [AlertNote] {
        let downs = events.filter { $0.event == .down }
        var out: [AlertNote] = []
        if downs.count >= groupMin {
            out.append(AlertNote(
                id: "group", title: "\(downs.count) checks down", body: downs.map(\.title).joined(separator: ", "),
                thread: "group", category: AlertCenter.groupCategory, check: nil, sound: downs.contains { $0.sound }
            ))
        } else {
            out += downs.map {
                AlertNote(
                    id: $0.id, title: $0.title, body: "Down", thread: $0.id,
                    category: $0.tunnel ? AlertCenter.tunnelCategory : AlertCenter.checkCategory, check: $0.id, sound: $0.sound
                )
            }
        }
        out += events.filter { $0.event == .recovered }.map {
            AlertNote(
                id: $0.id, title: $0.title, body: "Recovered", thread: $0.id,
                category: AlertCenter.checkCategory, check: $0.id, sound: $0.sound
            )
        }
        return out
    }
}

/// Smart notifications: debounce, repeat, quiet hours, grouping, offline and tunnel failures.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()
    nonisolated static let checkCategory = "check"
    nonisolated static let tunnelCategory = "tunnel"
    nonisolated static let groupCategory = "group"

    private var states: [String: AlertState] = [:]
    private var muted: [String: Date] = [:]
    private var baseline = true
    private var offline = false
    private var tunnelFailed = Set<String>()
    private var started = false

    /// Delegate, categories, authorization. App only (needs a bundle).
    func start() {
        guard !started else { return }
        started = true
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        let open = UNNotificationAction(identifier: "open", title: "Open", options: [.foreground])
        let mute = UNNotificationAction(identifier: "mute", title: "Mute 1h")
        let restart = UNNotificationAction(identifier: "restart", title: "Restart")
        c.setNotificationCategories([
            UNNotificationCategory(identifier: Self.checkCategory, actions: [open, mute], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.tunnelCategory, actions: [open, restart, mute], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.groupCategory, actions: [open], intentIdentifiers: []),
        ])
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NotificationCenter.default.addObserver(forName: TunnelLifecycle.didChange, object: nil, queue: .main) { [weak self] n in
            guard let id = n.userInfo?["id"] as? String else { return }
            MainActor.assumeIsolated { self?.tunnelChanged(id) }
        }
    }

    /// One poll. `down[id]` only for checks with a fresh, alertable result.
    func feed(_ down: [String: Bool], checks: [Check], global: Alerts?, online: Bool, now: Date = Date()) {
        guard started else { return }
        if !online {
            if !offline, !baseline {
                post(AlertNote(
                    id: "network", title: "Network offline", body: "Alerts paused until the network is back.",
                    thread: "network", category: Self.groupCategory, check: nil,
                    sound: AlertRule.resolve(global, nil).audible(at: now)
                ))
            }
            offline = true
            return
        }
        offline = false
        var events: [(id: String, title: String, event: AlertEvent, sound: Bool, tunnel: Bool)] = []
        for c in checks {
            guard let isDown = down[c.id] else { continue }
            let rule = AlertRule.resolve(global, c.alert)
            let (s, e) = AlertLogic.step(states[c.id] ?? AlertState(), down: isDown, rule: rule, now: now, baseline: baseline)
            states[c.id] = s
            guard let e, !isMuted(c.id, now) else { continue }
            events.append((c.id, c.title, e, rule.audible(at: now), SidebarScope.category(c) == "Tunnels"))
        }
        baseline = false
        AlertLogic.notes(events).forEach(post)
    }

    func post(_ n: AlertNote) {
        let c = UNMutableNotificationContent()
        c.title = n.title
        c.body = n.body
        c.threadIdentifier = n.thread
        c.categoryIdentifier = n.category
        if let id = n.check { c.userInfo = ["check": id] }
        c.sound = n.sound ? .default : nil
        if !n.sound { c.interruptionLevel = .passive }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "net.duyet.tiny-status.\(n.id)", content: c, trigger: nil)
        )
    }

    func sendTest() {
        start()
        post(AlertNote(
            id: "test", title: "TinyStatus", body: "Test notification", thread: "test",
            category: Self.groupCategory, check: nil, sound: true
        ))
    }

    func mute(_ id: String, for seconds: TimeInterval = 3600) {
        muted[id] = Date().addingTimeInterval(seconds)
    }

    /// Inspector line: on / off / muted until HH:MM.
    func statusText(_ c: Check, global: Alerts?, now: Date = Date()) -> String {
        if let until = muted[c.id], until > now {
            return "Muted until " + until.formatted(date: .omitted, time: .shortened)
        }
        return AlertRule.resolve(global, c.alert).enabled ? "On" : "Off"
    }

    private func isMuted(_ id: String, _ now: Date) -> Bool {
        guard let until = muted[id] else { return false }
        if until > now { return true }
        muted[id] = nil
        return false
    }

    /// Tunnel start failures alert right away, no debounce.
    private func tunnelChanged(_ id: String) {
        guard case let .failed(code, stderr) = TunnelLifecycle.shared.state(for: id) else {
            tunnelFailed.remove(id)
            return
        }
        guard tunnelFailed.insert(id).inserted, let c = Store.shared.allChecks().first(where: { $0.id == id }) else { return }
        let now = Date()
        let rule = AlertRule.resolve(Store.shared.alertsConfig, c.alert)
        guard rule.enabled, !isMuted(id, now) else { return }
        var s = states[id] ?? AlertState()
        s.alerted = true
        s.lastAlertAt = now
        states[id] = s
        let tail = TunnelLifecycle.tail(stderr, 120)
        post(AlertNote(
            id: id, title: "\(c.title) failed", body: tail.isEmpty ? "Exit \(code)" : "Exit \(code): \(tail)",
            thread: id, category: Self.tunnelCategory, check: id, sound: rule.audible(at: now)
        ))
    }

    private func handle(_ action: String, check id: String?) {
        switch action {
        case "mute":
            if let id { mute(id) }
        case "restart":
            if let id, let c = Store.shared.allChecks().first(where: { $0.id == id }) { TunnelLifecycle.shared.retry(c) }
        default:
            AppDelegate.instance?.showMain()
            if let id { MainState.shared.selectedId = id }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let id = response.notification.request.content.userInfo["check"] as? String
        Task { @MainActor in self.handle(action, check: id) }
        completionHandler()
    }
}
