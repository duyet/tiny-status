import AppKit

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
        ctx.setFillColor(color.withAlphaComponent(0.18).cgColor)
        if let copy = path.mutableCopy() {
            copy.addLine(to: CGPoint(x: b.maxX, y: b.minY))
            copy.addLine(to: CGPoint(x: b.minX, y: b.minY))
            copy.closeSubpath()
            ctx.addPath(copy)
            ctx.fillPath()
        }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }
}
