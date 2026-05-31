import AppKit

/// Custom menu row: brand-colored name + per-window remaining bar, % remaining, and reset time.
final class ProviderRowView: NSView {
    static let width: CGFloat = 342

    private let usage: ProviderUsage

    init(usage: ProviderUsage) {
        self.usage = usage
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height(for: usage)))
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }   // top-down layout

    // MARK: layout metrics
    private static let headerH: CGFloat = 30
    private static let rowH: CGFloat = 24
    private static let bottomPad: CGFloat = 8
    private static let leftX: CGFloat = 14
    private static let labelX: CGFloat = 14
    private static let barX: CGFloat = 78
    private static let barW: CGFloat = 128
    private static let percentX: CGFloat = 220
    private static let resetX: CGFloat = 258
    private static let rightPad: CGFloat = 14

    static func height(for usage: ProviderUsage) -> CGFloat {
        let rows = usage.state == .ok ? max(usage.windows.count, 1) : 1
        return headerH + CGFloat(rows) * rowH + bottomPad
    }

    // MARK: drawing
    override func draw(_ dirtyRect: NSRect) {
        drawHeader(in: NSRect(x: Self.leftX, y: 7, width: Self.resetX - Self.leftX - 8, height: 18))

        var tag = usage.plan?.capitalized ?? ""
        if usage.stale { tag = tag.isEmpty ? "stale" : "\(tag) · stale" }
        if !tag.isEmpty {
            drawText(tag, font: .systemFont(ofSize: 10.5, weight: .medium),
                     color: NSColor.labelColor.withAlphaComponent(0.5),
                     in: NSRect(x: Self.resetX, y: 9, width: Self.width - Self.resetX - Self.rightPad, height: 14))
        }

        guard usage.state == .ok, !usage.windows.isEmpty else {
            drawText(stateMessage(), font: .systemFont(ofSize: 11.5, weight: .regular),
                     color: NSColor.labelColor.withAlphaComponent(0.65),
                     in: NSRect(x: Self.leftX, y: Self.headerH + 4, width: Self.width - 28, height: 16))
            return
        }

        for (i, window) in usage.windows.enumerated() {
            let y = Self.headerH + CGFloat(i) * Self.rowH
            let remaining = max(0, min(100, 100 - window.usedPercent))

            drawText(window.displayLabel, font: .systemFont(ofSize: 11, weight: .medium),
                     color: NSColor.labelColor.withAlphaComponent(0.8),
                     in: NSRect(x: Self.labelX, y: y + 4, width: 56, height: 15))

            drawBar(remainingFraction: remaining / 100,
                    rect: NSRect(x: Self.barX, y: y + 6, width: Self.barW, height: 7))

            drawText("\(Int(remaining.rounded()))%", font: .systemFont(ofSize: 12, weight: .semibold),
                     color: .labelColor,
                     in: NSRect(x: Self.percentX, y: y + 3, width: 42, height: 15))

            if let reset = window.resetsAt {
                drawText("resets \(formatReset(reset, style: .menuRow))", font: .systemFont(ofSize: 10.5, weight: .regular),
                         color: NSColor.labelColor.withAlphaComponent(0.55),
                         in: NSRect(x: Self.resetX, y: y + 4, width: Self.width - Self.resetX - Self.rightPad, height: 14))
            }
        }
    }

    private func drawHeader(in rect: NSRect) {
        let s = NSMutableAttributedString(
            string: usage.name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.92)
            ]
        )
        if let status = usage.serviceStatus {
            s.append(NSAttributedString(
                string: " | \(status.providerName) status: \(status.level.displayText)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: status.level.displayColor
                ]
            ))
        }
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: s.length))
        s.draw(in: rect)
    }

    private func drawBar(remainingFraction: CGFloat, rect: NSRect) {
        let radius = rect.height / 2
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        guard remainingFraction > 0 else { return }
        let fillWidth = max(rect.height, rect.width * remainingFraction)
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        NSColor.labelColor.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    private func stateMessage() -> String {
        switch usage.state {
        case .needsToken:
            return usage.hint ?? "Needs token"
        case .authExpired: return "Auth expired — sign in to \(usage.name)"
        case .error(let message): return message
        case .ok: return ""
        }
    }

    private func drawText(_ s: String, font: NSFont, color: NSColor, in rect: NSRect, align: NSTextAlignment = .left) {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p]).draw(in: rect)
    }
}

private extension ServiceStatusLevel {
    var displayText: String {
        switch self {
        case .operational: return "operational"
        case .degraded: return "degraded"
        case .outage: return "outage"
        case .maintenance: return "maintenance"
        case .unknown: return "unknown"
        }
    }

    var displayColor: NSColor {
        switch self {
        case .operational: return NSColor.labelColor.withAlphaComponent(0.62)
        case .degraded: return NSColor.systemYellow.withAlphaComponent(0.85)
        case .outage: return NSColor.systemRed.withAlphaComponent(0.85)
        case .maintenance, .unknown: return NSColor.labelColor.withAlphaComponent(0.50)
        }
    }
}
