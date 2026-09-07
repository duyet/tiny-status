import AppKit

final class ImportController: NSViewController {
    private let text = NSTextView()
    private let hint = NSTextField(wrappingLabelWithString: "Paste a domain, URL, host:port, Tailscale name, IP, command, or JSON. TinyStatus infers HTTP health, TCP, or a custom command.")

    override func loadView() {
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.isRichText = false
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = text
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let add = NSButton(title: "Add checks", target: self, action: #selector(addChecks))
        add.keyEquivalent = "\r"
        add.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(hint)
        box.addSubview(scroll)
        box.addSubview(add)
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: hint.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: hint.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: add.topAnchor, constant: -12),
            add.trailingAnchor.constraint(equalTo: hint.trailingAnchor),
            add.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
        ])
        view = box
    }

    @objc func addChecks() {
        Store.shared.importPaste(text.string)
        view.window?.close()
    }
}
