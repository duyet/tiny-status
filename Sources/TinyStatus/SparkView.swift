import AppKit

/// Uptime Kuma–style heartbeat: one tick per poll.
final class HeartbeatView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var slots: Int = 32

    override var intrinsicContentSize: NSSize { NSSize(width: 148, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !values.isEmpty else { return }
        let shown = Array(values.suffix(slots))
        let n = shown.count
        let gap: CGFloat = 1.5
        let w = max(2, min(4, (bounds.width - gap * CGFloat(max(n - 1, 0))) / CGFloat(max(n, 1))))
        let total = CGFloat(n) * w + CGFloat(max(n - 1, 0)) * gap
        let origin = max(0, bounds.width - total)
        for (i, v) in shown.enumerated() {
            let x = origin + CGFloat(i) * (w + gap)
            let r = NSRect(x: x, y: 1, width: w, height: bounds.height - 2)
            let path = NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1)
            (v >= 0.99 ? NSColor.systemGreen : v >= 0.4 ? NSColor.systemOrange : NSColor.systemRed).setFill()
            path.fill()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class SparkView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 36) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard values.count > 1, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds.insetBy(dx: 2, dy: 4)
        let last = values.last ?? 0
        let color: NSColor = last >= 0.99 ? .systemGreen : last >= 0.4 ? .systemOrange : .systemRed
        let path = CGMutablePath()
        for (i, v) in values.enumerated() {
            let x = b.minX + b.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = b.minY + b.height * CGFloat(min(1, max(0, v)))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.setFillColor(color.withAlphaComponent(0.16).cgColor)
        if let copy = path.mutableCopy() {
            copy.addLine(to: CGPoint(x: b.maxX, y: b.minY))
            copy.addLine(to: CGPoint(x: b.minX, y: b.minY))
            copy.closeSubpath()
            ctx.addPath(copy)
            ctx.fillPath()
        }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }
}

final class BarChartView: NSView {
    var values: [(label: String, value: Double, ok: Bool)] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !values.isEmpty else { return }
        let padL: CGFloat = 8, padR: CGFloat = 8, padT: CGFloat = 16, padB: CGFloat = 28
        let plot = NSRect(x: padL, y: padT, width: bounds.width - padL - padR, height: bounds.height - padT - padB)
        let maxV = max(values.map(\.value).max() ?? 1, 1)
        let gap: CGFloat = 10
        let barW = max(8, (plot.width - gap * CGFloat(values.count + 1)) / CGFloat(values.count))
        let grid = NSColor.separatorColor.withAlphaComponent(0.35)
        grid.setStroke()
        for i in 0...3 {
            let y = plot.maxY - plot.height * CGFloat(i) / 3
            let p = NSBezierPath()
            p.move(to: NSPoint(x: plot.minX, y: y))
            p.line(to: NSPoint(x: plot.maxX, y: y))
            p.lineWidth = 1
            p.stroke()
        }
        for (i, item) in values.enumerated() {
            let h = plot.height * CGFloat(item.value / maxV)
            let x = plot.minX + gap + CGFloat(i) * (barW + gap)
            let r = NSRect(x: x, y: plot.maxY - h, width: barW, height: max(h, 2))
            let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            (item.ok ? NSColor.systemBlue : NSColor.systemOrange).setFill()
            path.fill()
            let label = item.label as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let sz = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: x + (barW - sz.width) / 2, y: plot.maxY + 6),
                withAttributes: attrs
            )
        }
    }
}
