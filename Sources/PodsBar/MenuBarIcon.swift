import AppKit

enum DisplayMode: String, CaseIterable, Identifiable {
    case podsAndBoth   // 56L ▯▮ R62
    case podsAndLowest // ▯▮ L56
    case podsOnly      // ▯▮

    var id: String { rawValue }

    var label: String {
        switch self {
        case .podsAndBoth:   return "Both buds"
        case .podsAndLowest: return "Lowest bud"
        case .podsOnly:      return "Icon only"
        }
    }
}

/// Draws the menu bar glyph: each bud's charge as a capsule that fills up, with that bud's
/// percentage on its own side — reading `56L ▯▮ R62`.
///
/// Both letters sit on the inside, against the capsules they label, so each letter is next to
/// its own pod rather than stranded at the far edge of the glyph.
///
/// The image is always a *template*, so macOS tints it itself for light/dark menu bars, for
/// the highlighted state, and for reduced-transparency — that's what makes it look native
/// rather than pasted on. It also means the glyph is drawn once and never needs re-rendering
/// when the appearance changes. The cost is that it can't be red at low battery; a near-empty
/// capsule reads clearly enough, and the popover shows red there.
@MainActor
enum MenuBarIcon {

    static let lowThreshold = 20

    private struct CacheKey: Equatable {
        let left: Int?
        let right: Int?
        let single: Int?
        let mode: DisplayMode
        let dimmed: Bool
    }

    // Retain just the current glyph, not an image for every battery combination.
    // Refresh/freshness changes otherwise redraw an identical AppKit image.
    private static var cached: (key: CacheKey, image: NSImage)?

    private enum Metrics {
        static let height: CGFloat = 18
        static let podWidth: CGFloat = 7
        static let podHeight: CGFloat = 13
        static let podGap: CGFloat = 2.5
        static let textGap: CGFloat = 3.5
        static let lineWidth: CGFloat = 1
        static let minFill: CGFloat = 1.5
        static let numberSize: CGFloat = 10
        /// The L/R letters sit smaller and lighter than the numbers so the numbers stay dominant.
        static let letterSize: CGFloat = 8
        static let letterAlpha: CGFloat = 0.55
        static let letterKern: CGFloat = 0.5
    }

    /// The glyph shown when nothing is connected: two empty, dimmed pods.
    static func disconnected() -> NSImage {
        render(left: nil, right: nil, single: nil, mode: .podsOnly, dimmed: true)
    }

    static func image(for device: PodsDevice, mode: DisplayMode) -> NSImage {
        render(left: device.left, right: device.right, single: device.single, mode: mode, dimmed: false)
    }

    // MARK: - Layout

    private static func render(
        left: Int?, right: Int?, single: Int?, mode: DisplayMode, dimmed: Bool
    ) -> NSImage {
        let key = CacheKey(left: left, right: right, single: single, mode: mode, dimmed: dimmed)
        if let cached, cached.key == key { return cached.image }
        // A single-cell device (AirPods Max, most Beats) gets one pod instead of two.
        let isSingle = single != nil && left == nil && right == nil
        let levels: [Int?] = isSingle ? [single] : [left, right]

        let (leading, trailing) = textSegments(
            left: left, right: right, single: single, isSingle: isSingle, mode: mode
        )

        let leadingWidth = leading.map { ceil($0.size().width) } ?? 0
        let trailingWidth = trailing.map { ceil($0.size().width) } ?? 0
        let podsWidth = CGFloat(levels.count) * Metrics.podWidth
            + CGFloat(max(0, levels.count - 1)) * Metrics.podGap

        let podsX = leadingWidth + (leading == nil ? 0 : Metrics.textGap)
        let width = podsX + podsWidth + (trailing == nil ? 0 : Metrics.textGap + trailingWidth)

        let image = NSImage(size: NSSize(width: width, height: Metrics.height), flipped: false) { _ in
            if let leading { draw(leading, atX: 0) }

            let podY = (Metrics.height - Metrics.podHeight) / 2
            for (index, level) in levels.enumerated() {
                let x = podsX + CGFloat(index) * (Metrics.podWidth + Metrics.podGap)
                drawPod(
                    in: NSRect(x: x, y: podY, width: Metrics.podWidth, height: Metrics.podHeight),
                    level: level, dimmed: dimmed
                )
            }

            if let trailing { draw(trailing, atX: podsX + podsWidth + Metrics.textGap) }
            return true
        }

        image.isTemplate = true
        cached = (key, image)
        return image
    }

    /// What sits to the left of the pods, and what sits to the right.
    private static func textSegments(
        left: Int?, right: Int?, single: Int?, isSingle: Bool, mode: DisplayMode
    ) -> (NSAttributedString?, NSAttributedString?) {
        switch mode {
        case .podsOnly:
            return (nil, nil)

        case .podsAndLowest:
            if isSingle { return (nil, single.map { segment(letter: nil, number: $0, letterFirst: true) }) }
            // Name the bud that's actually running out, so "L56" tells you which one to worry about.
            let lowest = [("L", left), ("R", right)]
                .compactMap { letter, level in level.map { (letter, $0) } }
                .min { $0.1 < $1.1 }
            return (nil, lowest.map { segment(letter: $0.0, number: $0.1, letterFirst: true) })

        case .podsAndBoth:
            if isSingle { return (nil, single.map { segment(letter: nil, number: $0, letterFirst: true) }) }
            // Each number sits on its own bud's side; a missing bud reserves no space.
            return (left.map { segment(letter: "L", number: $0, letterFirst: false) },
                    right.map { segment(letter: "R", number: $0, letterFirst: true) })
        }
    }

    /// `letterFirst` false puts the letter after the number (`56L`), which is how the left
    /// bud is drawn so its letter ends up against the pods rather than at the outer edge.
    private static func segment(letter: String?, number: Int, letterFirst: Bool) -> NSAttributedString {
        guard let letter else {
            return NSAttributedString(string: "\(number)", attributes: [
                .font: numberFont, .foregroundColor: NSColor.black,
            ])
        }

        let letterRun = NSAttributedString(string: letter, attributes: [
            .font: NSFont.systemFont(ofSize: Metrics.letterSize, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(Metrics.letterAlpha),
        ])
        let numberRun = NSAttributedString(string: "\(number)", attributes: [
            .font: numberFont,
            .foregroundColor: NSColor.black,
        ])

        let first = letterFirst ? letterRun : numberRun
        let result = NSMutableAttributedString(attributedString: first)
        result.append(letterFirst ? numberRun : letterRun)

        // Kern only the character immediately before the join. Applying it to the whole run
        // would space out every digit of "100" as well.
        result.addAttribute(.kern, value: Metrics.letterKern,
                            range: NSRange(location: first.length - 1, length: 1))
        return result
    }

    private static var numberFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: Metrics.numberSize, weight: .medium)
    }

    // MARK: - Drawing

    private static func draw(_ text: NSAttributedString, atX x: CGFloat) {
        let size = text.size()
        text.draw(at: NSPoint(x: x, y: (Metrics.height - size.height) / 2))
    }

    private static func drawPod(in frame: NSRect, level: Int?, dimmed: Bool) {
        let radius = frame.width / 2
        let outline = NSBezierPath(roundedRect: frame.insetBy(dx: Metrics.lineWidth / 2,
                                                              dy: Metrics.lineWidth / 2),
                                   xRadius: radius, yRadius: radius)
        outline.lineWidth = Metrics.lineWidth

        NSColor.black.withAlphaComponent(dimmed ? 0.45 : 1).setStroke()
        outline.stroke()

        guard let level, level > 0 else { return }

        // Fill from the bottom up, clipped to the capsule so the fill keeps the rounded ends.
        let inset = frame.insetBy(dx: Metrics.lineWidth + 0.5, dy: Metrics.lineWidth + 0.5)
        // Keep a sliver visible at 1-4%, otherwise "nearly dead" looks identical to "empty".
        let fillHeight = max(Metrics.minFill, inset.height * CGFloat(min(level, 100)) / 100)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: inset, xRadius: inset.width / 2, yRadius: inset.width / 2).addClip()
        NSColor.black.setFill()
        NSRect(x: inset.minX, y: inset.minY, width: inset.width, height: fillHeight).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
