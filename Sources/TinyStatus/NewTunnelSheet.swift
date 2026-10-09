import AppKit

/// Pure builder for an `ssh -L` tunnel check. Kept separate from the sheet for tests.
enum TunnelSpec {
    struct Input {
        var name: String
        var localPort: String
        var remote: String
        var via: String
    }

    static func port(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.allSatisfy(\.isASCII), t.allSatisfy(\.isNumber), let n = Int(t), (1 ... 65535).contains(n) else {
            return nil
        }
        return n
    }

    /// Splits `host:port` on the last colon.
    static func hostPort(_ s: String) -> (host: String, port: Int)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let i = t.lastIndex(of: ":") else { return nil }
        let host = String(t[..<i])
        guard !host.isEmpty, !host.contains(where: \.isWhitespace), let p = port(String(t[t.index(after: i)...])) else {
            return nil
        }
        return (host, p)
    }

    /// First problem with the input, or nil when valid.
    static func validate(_ i: Input) -> String? {
        if i.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Name is required." }
        if port(i.localPort) == nil { return "Local port must be a number 1–65535." }
        if hostPort(i.remote) == nil { return "Remote must be host:port with port 1–65535." }
        let via = i.via.trimmingCharacters(in: .whitespaces)
        if via.isEmpty || via.contains(where: \.isWhitespace) || via.hasPrefix("-") { return "Via must be an ssh host." }
        return nil
    }

    static func check(_ i: Input) -> Check? {
        guard validate(i) == nil, let lport = port(i.localPort), let r = hostPort(i.remote) else { return nil }
        let name = i.name.trimmingCharacters(in: .whitespaces)
        let forward = "\(lport):\(r.host):\(r.port)"
        var c = Check(id: slug(name), title: name, kind: .tcp, host: "127.0.0.1", port: lport)
        c.tags = ["tunnel"]
        c.actions = [
            CheckAction(id: "start", title: "Connect", command: ["/usr/bin/ssh", "-N", "-L", forward, i.via.trimmingCharacters(in: .whitespaces)], when: "down", icon: "play.fill"),
            CheckAction(id: "stop", title: "Disconnect", command: ["/usr/bin/pkill", "-f", forward], when: "up", icon: "stop.fill"),
        ]
        return c
    }

    static func slug(_ s: String) -> String {
        let parts = s.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return parts.isEmpty ? "tunnel" : parts.joined(separator: "-")
    }
}

/// Sheet: Name, Local port, Remote host:port, Via → appends a tunnel check to `checks[]`.
final class NewTunnelSheet: NSViewController {
    private let name = NSTextField()
    private let lport = NSTextField()
    private let remote = NSTextField()
    private let via = NSTextField()
    private let error = NSTextField(labelWithString: "")
    private let create = NSButton(title: "Create", target: nil, action: nil)

    static func present(on window: NSWindow) {
        let vc = NewTunnelSheet()
        let sheet = NSWindow(contentViewController: vc)
        sheet.title = "New Tunnel"
        window.beginSheet(sheet)
    }

    override func loadView() {
        name.placeholderString = "Web tunnel"
        lport.placeholderString = "8443"
        remote.placeholderString = "127.0.0.1:443"
        via.placeholderString = "my-machine.tailnet.ts.net"
        for f in [name, lport, remote, via] {
            f.target = self
            f.action = #selector(changed)
            f.delegate = self
        }
        error.textColor = .systemRed
        error.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Name:"), name],
            [NSTextField(labelWithString: "Local port:"), lport],
            [NSTextField(labelWithString: "Remote host:port:"), remote],
            [NSTextField(labelWithString: "Via (ssh host):"), via],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 240
        grid.rowSpacing = 8

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSheet))
        cancel.keyEquivalent = "\u{1b}"
        create.target = self
        create.action = #selector(createCheck)
        create.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, create])

        let stack = NSStackView(views: [grid, error, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        view = stack
        changed()
    }

    private var input: TunnelSpec.Input {
        .init(name: name.stringValue, localPort: lport.stringValue, remote: remote.stringValue, via: via.stringValue)
    }

    @objc private func changed() {
        let msg = TunnelSpec.validate(input)
        create.isEnabled = msg == nil
        // Hide the error until the user has typed something.
        let typed = [name, lport, remote, via].contains { !$0.stringValue.isEmpty }
        error.stringValue = typed ? (msg ?? "") : ""
    }

    @objc private func createCheck() {
        guard let c = TunnelSpec.check(input) else { changed(); return }
        if Store.shared.allChecks().contains(where: { $0.id == c.id }) {
            error.stringValue = "A check with id \"\(c.id)\" already exists."
            return
        }
        Store.shared.appendChecks([c])
        close()
    }

    @objc private func cancelSheet() { close() }

    private func close() {
        guard let w = view.window else { return }
        w.sheetParent?.endSheet(w)
    }
}

extension NewTunnelSheet: NSTextFieldDelegate {
    func controlTextDidChange(_: Notification) { changed() }
}
