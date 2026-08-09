// token_hud/Overlay/FocusGauges.swift
import SwiftUI

/// The focus card's main usage gauge. One entry point that renders whichever
/// `FocusGaugeStyle` the user picked; every style encodes the same `fraction`
/// (0...1 usage) and takes its color from the provider `accent`, so switching
/// styles never changes the card's layout or meaning.
///
/// Animation is driven by a single `TimelineView` clock and every style is a
/// pure function of `(t, fraction, size)`. Under Reduce Motion the clock is
/// pinned to 0, yielding a still frame of the same drawing.
struct FocusGauge: View {
    let style: FocusGaugeStyle
    let fraction: Double
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            canvas(t: 0)
        } else {
            TimelineView(.animation) { timeline in
                canvas(t: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func canvas(t: TimeInterval) -> some View {
        Canvas { ctx, size in
            guard size.width > 1, size.height > 1 else { return }
            let f = min(1, max(0, fraction))
            switch style {
            case .glowBar:   Self.drawGlowBar(&ctx, size, f, t, accent)
            case .wave:      Self.drawWave(&ctx, size, f, t, accent)
            case .aurora:    Self.drawAurora(&ctx, size, f, t, accent)
            case .softDots:  Self.drawSoftDots(&ctx, size, f, t, accent)
            case .liquid:    Self.drawLiquid(&ctx, size, f, t, accent)
            case .particles: Self.drawParticles(&ctx, size, f, t, accent)
            case .arc:       Self.drawArc(&ctx, size, f, t, accent)
            case .fiber:     Self.drawFiber(&ctx, size, f, t, accent)
            }
        }
    }
}

// MARK: - Daily usage bars

/// Per-day consumption as bars, with today highlighted. Used for providers
/// whose only real signals are a cumulative counter and a reset time — a single
/// average hides whether today is unusually heavy, which is the thing worth
/// noticing.
struct DailyUsageChart: View {
    let days: [DailyUsage]
    let accent: Color

    @Environment(\.panelAdaptiveScale) private var scale

    private var peak: Double { max(days.map(\.amount).max() ?? 0, 1) }
    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4 * scale) {
            ForEach(days) { day in
                let isToday = Calendar.current.isDate(day.day, inSameDayAs: todayStart)
                let isFuture = day.day > todayStart
                VStack(spacing: 3 * scale) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isFuture ? Color.white.opacity(0.10) : accent)
                        .opacity(isFuture ? 1 : (isToday ? 1 : 0.55))
                        .shadow(color: isToday ? accent.opacity(0.8) : .clear, radius: 5)
                        .frame(height: max(2, CGFloat(day.amount / peak) * 30 * scale))
                    Text(Self.label(for: day.day, isToday: isToday))
                        .font(.system(size: 7.5 * scale, weight: isToday ? .bold : .medium))
                        .foregroundStyle(.white.opacity(isToday ? 0.95 : 0.35))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private static func label(for day: Date, isToday: Bool) -> String {
        if isToday { return "今天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "E"
        return f.string(from: day)
    }
}

// MARK: - Styles

private extension FocusGauge {

    // A · continuous glow bar with a sweeping highlight
    static func drawGlowBar(_ ctx: inout GraphicsContext, _ size: CGSize,
                            _ f: Double, _ t: TimeInterval, _ accent: Color) {
        let h = min(8, size.height)
        let y = (size.height - h) / 2
        let track = Path(roundedRect: CGRect(x: 0, y: y, width: size.width, height: h),
                         cornerRadius: h / 2)
        ctx.fill(track, with: .color(.white.opacity(0.10)))

        let fw = size.width * f
        guard fw > 1 else { return }
        let fill = Path(roundedRect: CGRect(x: 0, y: y, width: fw, height: h), cornerRadius: h / 2)

        var glow = ctx
        glow.addFilter(.shadow(color: accent.opacity(0.75), radius: 8))
        glow.fill(fill, with: .linearGradient(
            Gradient(colors: [accent.opacity(0.5), accent, Color.white.opacity(0.92)]),
            startPoint: .zero, endPoint: CGPoint(x: fw, y: 0)))

        // Highlight sweep, clipped to the filled region.
        var sheen = ctx
        sheen.clip(to: fill)
        sheen.blendMode = .plusLighter
        let period = 2.2
        let p = (t.truncatingRemainder(dividingBy: period)) / period
        let sw = max(20, fw * 0.3)
        let sx = -sw + (fw + sw) * p
        sheen.fill(Path(CGRect(x: sx, y: y, width: sw, height: h)),
                   with: .linearGradient(
                    Gradient(colors: [.clear, .white.opacity(0.5), .clear]),
                    startPoint: CGPoint(x: sx, y: 0), endPoint: CGPoint(x: sx + sw, y: 0)))
    }

    // B · flowing wave with a glow pool underneath
    static func drawWave(_ ctx: inout GraphicsContext, _ size: CGSize,
                         _ f: Double, _ t: TimeInterval, _ accent: Color) {
        let mid = size.height * 0.55
        let amp = min(7, size.height * 0.22)
        var line = Path()
        var x: CGFloat = 0
        line.move(to: CGPoint(x: 0, y: mid))
        while x <= size.width {
            let u = x / max(1, size.width)
            let y = mid - sin(u * .pi * 4 + t * 1.5) * amp * (0.55 + 0.45 * sin(u * 3 + t * 0.9))
            line.addLine(to: CGPoint(x: x, y: y))
            x += 3
        }

        // Dim baseline across the full width.
        ctx.stroke(line, with: .color(accent.opacity(0.22)), lineWidth: 1.6)

        let fw = size.width * f
        guard fw > 1 else { return }
        var area = line
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()

        var lit = ctx
        lit.clip(to: Path(CGRect(x: 0, y: 0, width: fw, height: size.height)))
        lit.fill(area, with: .linearGradient(
            Gradient(colors: [accent.opacity(0.5), accent.opacity(0)]),
            startPoint: CGPoint(x: 0, y: mid - amp), endPoint: CGPoint(x: 0, y: size.height)))
        lit.addFilter(.shadow(color: accent.opacity(0.8), radius: 5))
        lit.stroke(line, with: .color(Color.white.opacity(0.85)), lineWidth: 1.8)
    }

    // C · edgeless drifting haze
    static func drawAurora(_ ctx: inout GraphicsContext, _ size: CGSize,
                           _ f: Double, _ t: TimeInterval, _ accent: Color) {
        let fw = size.width * f
        guard fw > 1 else { return }
        var layer = ctx
        layer.clip(to: Path(CGRect(x: 0, y: 0, width: fw, height: size.height)))
        layer.addFilter(.blur(radius: 9))
        layer.blendMode = .plusLighter

        let blobs: [(CGFloat, CGFloat, Double, Color)] = [
            (0.30, 0.52, 0.55, accent.opacity(0.85)),
            (0.62, 0.44, 0.42, Color.white.opacity(0.30)),
            (0.80, 0.58, 0.50, accent.opacity(0.65))
        ]
        for (i, b) in blobs.enumerated() {
            let phase = t * (0.5 + Double(i) * 0.13) + Double(i)
            let cx = size.width * (b.0 + 0.16 * CGFloat(cos(phase)))
            let cy = size.height * (b.1 + 0.16 * CGFloat(sin(phase * 1.2)))
            let rx = size.width * CGFloat(b.2)
            let ry = size.height * 0.55
            let rect = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
            layer.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [b.3, b.3.opacity(0)]),
                center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: rx))
        }
    }

    // D · rounded glowing columns with a travelling pulse
    static func drawSoftDots(_ ctx: inout GraphicsContext, _ size: CGSize,
                             _ f: Double, _ t: TimeInterval, _ accent: Color) {
        let count = 34
        let gap: CGFloat = 3
        let w = max(1.5, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
        let head = (t * 7).truncatingRemainder(dividingBy: Double(count))
        for i in 0..<count {
            let env = 0.45 + 0.55 * abs(sin(Double(i) * 0.42))
            let h = (0.35 + 0.65 * env) * size.height
            let x = CGFloat(i) * (w + gap)
            let rect = CGRect(x: x, y: (size.height - h) / 2, width: w, height: h)
            let bar = Path(roundedRect: rect, cornerRadius: w / 2)

            let lit = Double(i) / Double(count) < f
            var d = abs(Double(i) - head)
            d = min(d, Double(count) - d)
            let hot = max(0, 1 - d / 5)

            if lit {
                var g = ctx
                if hot > 0.25 { g.addFilter(.shadow(color: accent.opacity(0.9), radius: 6 * hot)) }
                g.fill(bar, with: .color(accent.opacity(0.45 + 0.55 * hot)))
            } else {
                ctx.fill(bar, with: .color(.white.opacity(0.14)))
            }
        }
    }

    // E · sloshing liquid in a capsule
    static func drawLiquid(_ ctx: inout GraphicsContext, _ size: CGSize,
                           _ f: Double, _ t: TimeInterval, _ accent: Color) {
        let h = min(18, size.height)
        let y = (size.height - h) / 2
        let capsule = Path(roundedRect: CGRect(x: 0, y: y, width: size.width, height: h),
                           cornerRadius: h / 2)
        ctx.fill(capsule, with: .color(.white.opacity(0.09)))

        let fw = size.width * f
        guard fw > 2 else { return }
        var body = ctx
        body.clip(to: capsule)
        body.clip(to: Path(CGRect(x: 0, y: 0, width: fw, height: size.height)))

        // Wavy surface, higher amplitude near the leading edge (surface tension).
        var liquid = Path()
        liquid.move(to: CGPoint(x: 0, y: size.height))
        var x: CGFloat = 0
        while x <= fw {
            let edge = 1 - min(1, Double((fw - x) / max(1, h)))
            let surf = y + h * 0.28
                + CGFloat(sin(Double(x) / 22 + t * 1.6) * 1.8)
                + CGFloat(sin(Double(x) / 9 - t * 2.1) * 0.9)
                - CGFloat(edge * 2.2)
            liquid.addLine(to: CGPoint(x: x, y: surf))
            x += 3
        }
        liquid.addLine(to: CGPoint(x: fw, y: size.height))
        liquid.closeSubpath()

        body.addFilter(.shadow(color: accent.opacity(0.6), radius: 6))
        body.fill(liquid, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.85), accent, accent.opacity(0.75)]),
            startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + h)))
    }

    // F · particles streaming along a track
    static func drawParticles(_ ctx: inout GraphicsContext, _ size: CGSize,
                              _ f: Double, _ t: TimeInterval, _ accent: Color) {
        let mid = size.height / 2
        ctx.fill(Path(roundedRect: CGRect(x: 0, y: mid - 0.75, width: size.width, height: 1.5),
                      cornerRadius: 0.75),
                 with: .color(.white.opacity(0.10)))

        let fw = size.width * f
        guard fw > 2 else { return }
        var layer = ctx
        layer.blendMode = .plusLighter
        layer.addFilter(.shadow(color: accent.opacity(0.9), radius: 4))

        let count = 26
        for i in 0..<count {
            // Deterministic per-particle speed/offset — no stored state.
            let seed = Double(i)
            let speed = 0.16 + (seed.truncatingRemainder(dividingBy: 7)) * 0.035
            let phase = ((t * speed) + seed * 0.137).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(phase) * fw
            let yOff = CGFloat(sin(seed * 2.3)) * (size.height * 0.18)
            let r = 1.0 + (seed.truncatingRemainder(dividingBy: 3)) * 0.7
            // Fade in at the start and out near the leading edge.
            let fade = min(1, phase / 0.12) * min(1, (1 - phase) / 0.25)
            let rect = CGRect(x: x - r, y: mid + yOff - r, width: r * 2, height: r * 2)
            layer.fill(Path(ellipseIn: rect),
                       with: .color(accent.opacity(0.35 + 0.65 * fade)))
        }
    }

    // G · sweeping arc with a light running along it
    static func drawArc(_ ctx: inout GraphicsContext, _ size: CGSize,
                        _ f: Double, _ t: TimeInterval, _ accent: Color) {
        let inset: CGFloat = 3
        let p0 = CGPoint(x: inset, y: size.height * 0.85)
        let p1 = CGPoint(x: size.width / 2, y: size.height * 0.05)
        let p2 = CGPoint(x: size.width - inset, y: size.height * 0.85)

        func point(_ u: CGFloat) -> CGPoint {
            let mt = 1 - u
            return CGPoint(x: mt * mt * p0.x + 2 * mt * u * p1.x + u * u * p2.x,
                           y: mt * mt * p0.y + 2 * mt * u * p1.y + u * u * p2.y)
        }

        var full = Path()
        full.move(to: p0)
        full.addQuadCurve(to: p2, control: p1)
        ctx.stroke(full, with: .color(.white.opacity(0.10)), lineWidth: 2)

        guard f > 0.01 else { return }
        var lit = Path()
        lit.move(to: p0)
        var u: CGFloat = 0
        while u <= CGFloat(f) {
            lit.addLine(to: point(u))
            u += 0.01
        }
        var glow = ctx
        glow.addFilter(.shadow(color: accent.opacity(0.8), radius: 6))
        glow.stroke(lit, with: .linearGradient(
            Gradient(colors: [accent.opacity(0.45), Color.white.opacity(0.95), accent.opacity(0.6)]),
            startPoint: p0, endPoint: p2),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

        // Light bead travelling along the lit portion.
        let travel = CGFloat((t * 0.22).truncatingRemainder(dividingBy: 1)) * CGFloat(f)
        let c = point(travel)
        var bead = ctx
        bead.addFilter(.shadow(color: accent.opacity(0.95), radius: 7))
        bead.fill(Path(ellipseIn: CGRect(x: c.x - 2.6, y: c.y - 2.6, width: 5.2, height: 5.2)),
                  with: .color(.white))
    }

    // H · parallel light strands
    static func drawFiber(_ ctx: inout GraphicsContext, _ size: CGSize,
                          _ f: Double, _ t: TimeInterval, _ accent: Color) {
        let mid = size.height / 2
        let fw = size.width * f
        let strands = 4
        for i in 0..<strands {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: mid))
            var x: CGFloat = 0
            let amp = (size.height * 0.16) + CGFloat(i) * (size.height * 0.06)
            let phase = t * 0.9 + Double(i) * 1.3
            while x <= size.width {
                let u = Double(x / max(1, size.width))
                // Pinch to the centre line at both ends, like a bundled fiber.
                let y = mid + CGFloat(sin(u * 8 + phase) * sin(u * .pi)) * amp
                path.addLine(to: CGPoint(x: x, y: y))
                x += 4
            }
            ctx.stroke(path, with: .color(accent.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 2.2 - CGFloat(i) * 0.4, lineCap: .round))

            guard fw > 1 else { continue }
            var lit = ctx
            lit.clip(to: Path(CGRect(x: 0, y: 0, width: fw, height: size.height)))
            lit.addFilter(.shadow(color: accent.opacity(0.7), radius: 4))
            let tint = i % 2 == 0 ? Color.white.opacity(0.85) : accent
            lit.stroke(path, with: .color(tint.opacity(0.9 - Double(i) * 0.15)),
                       style: StrokeStyle(lineWidth: 2.2 - CGFloat(i) * 0.4, lineCap: .round))
        }
    }
}
