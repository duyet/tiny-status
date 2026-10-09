import AppKit
import Combine
import SwiftUI

/// Menu bar extra: colored dot + "up/total", click opens a popover of checks.
@MainActor
final class MenuBarController: NSObject {
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    private let store = Store.shared

    override init() {
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarPopover(store: store, close: { [weak self] in self?.popover.performClose(nil) }))
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &bag)
        refresh()
    }

    func refresh() {
        guard store.showMenuBar else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            popover.performClose(nil)
            return
        }
        if item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.button?.target = self
            i.button?.action = #selector(toggle)
            i.button?.imagePosition = .imageLeading
            item = i
        }
        let total = store.healthCheckTotal
        let color: NSColor = total == 0 ? .secondaryLabelColor : store.allOK ? .systemGreen : .systemRed
        item?.button?.image = Self.dot(color)
        item?.button?.title = total == 0 ? "" : " \(store.healthCheckUp)/\(total)"
        item?.button?.toolTip = store.healthCheckSummary
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private static func dot(_ color: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }
}

@MainActor
private final class LifecycleTicker: ObservableObject {
    static let shared = LifecycleTicker()
    @Published var tick = 0
    private init() {
        NotificationCenter.default.addObserver(forName: TunnelLifecycle.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick += 1 }
        }
    }
}

private struct PopoverItem: Identifiable {
    var id: String
    var title: String
    var up: Bool
    var ms: Double?
    var actions: [CheckAction]
    var isTunnel = false
}

struct MenuBarPopover: View {
    @ObservedObject var store: Store
    var close: () -> Void
    @ObservedObject private var lifecycle = LifecycleTicker.shared

    private var items: [PopoverItem] {
        let t = store.tunnels.filter(\.enabled).map {
            PopoverItem(id: $0.id, title: $0.title, up: $0.up, ms: $0.ms, actions: $0.actions, isTunnel: true)
        }
        let d = store.deploys.filter(\.enabled).map {
            PopoverItem(id: $0.id, title: $0.title, up: $0.up, ms: $0.avgMs, actions: $0.actions)
        }
        let all = t + d
        return all.filter { !$0.up } + all.filter(\.up)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if items.isEmpty {
                        Text("No checks").foregroundStyle(.secondary).padding(20)
                    }
                    ForEach(items) { row($0) }
                }
            }
            .frame(maxHeight: 360)
            Divider()
            HStack {
                Button("Check all") { store.poll() }
                Spacer()
                Button("Open window") {
                    close()
                    AppDelegate.instance?.showMain()
                }
            }
            .padding(10)
        }
        .frame(width: 320)
    }

    private func run(_ r: PopoverItem, _ action: CheckAction) {
        if r.isTunnel, action.id == "start" || action.id == "stop",
           let check = store.allChecks().first(where: { $0.id == r.id })
        {
            if action.id == "start" { TunnelLifecycle.shared.start(check) } else { TunnelLifecycle.shared.stop(check) }
        } else {
            store.runAction(checkId: r.id, actionId: action.id)
        }
    }

    private func row(_ r: PopoverItem) -> some View {
        _ = lifecycle.tick
        let action = r.actions.first { $0.isVisible(up: r.up) }
        return HStack(spacing: 8) {
            Circle().fill(r.up ? Color.green : Color.red).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title).lineLimit(1)
                if r.isTunnel {
                    Text(TunnelLifecycle.shared.statusText(for: r.id))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if r.up {
                if let ms = r.ms {
                    Text("\(Int(ms)) ms").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let action, !r.up || r.isTunnel && action.id == "stop" {
                Button(action.title) { run(r, action) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(r.up ? Color.clear : Color.red.opacity(0.12))
    }
}
