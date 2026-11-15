import SwiftUI

/// 気圧のグラフ。縦軸は気圧そのものではなく、1時間あたりの変化量。
/// 音の波形の振幅がエネルギーであるのと同じで、大きく振れているほど速く動いている。
/// 赤い縦線が現在、黒い横線が「変化なし」。
struct PressureWave: View {
    let forecast: Forecast
    let window: ClosedRange<Int>
    /// なぞっている位置。nil なら現在。
    @Binding var scrub: Int?

    private let mirror = 0.45
    /// 目盛りの下限 hPa/時。これ以下は縮めずに見せる。
    private let floorRate = 0.5

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(&ctx, size) }
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let t = min(max(0, v.location.x / max(geo.size.width, 1)), 1)
                            scrub = window.lowerBound + Int((t * Double(window.count - 1)).rounded())
                        }
                        .onEnded { _ in scrub = nil }
                )
        }
    }

    // MARK: -

    /// 1時間でどれだけ動いたか。添字は forecast.pressure と同じ。
    private var rate: [Double?] {
        var out = [Double?](repeating: nil, count: forecast.pressure.count)
        for i in 1..<max(1, forecast.pressure.count) {
            if let a = forecast.pressure[safe: i - 1] ?? nil, let b = forecast.pressure[safe: i] ?? nil {
                out[i] = b - a
            }
        }
        return out
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let inset: CGFloat = 10
        let W = size.width - inset * 2
        let H = size.height - inset * 2
        guard W > 10, H > 10, window.count > 1 else { return }

        let now = forecast.nowIndex
        let r = rate
        let span = Double(window.count - 1)

        let maxAbs = window.compactMap { r[safe: $0] ?? nil }.map(abs).max() ?? 0
        let lim = max(floorRate, maxAbs * 1.02)

        let yb = inset + H / 2
        let amp = H * 0.45
        func x(_ i: Int) -> CGFloat { inset + CGFloat(Double(i - window.lowerBound) / span) * W }
        func dev(_ v: Double?) -> CGFloat { -CGFloat((v ?? 0) / lim) * amp }

        // 下敷きは時間の罫。1時間ごとに引き、3時間ごとを少し濃くする。
        for i in window {
            let strong = (i - now) % 3 == 0
            var p = Path()
            p.move(to: CGPoint(x: x(i), y: inset))
            p.addLine(to: CGPoint(x: x(i), y: inset + H))
            ctx.stroke(p, with: .color(Theme.ink.opacity(strong ? 0.20 : 0.10)),
                       lineWidth: strong ? 0.8 : 0.6)
        }

        // 要注意の時間帯
        for band in Risk.cautionBands(forecast.pressure) {
            let s = max(band.lowerBound, window.lowerBound)
            let e = min(band.upperBound, window.upperBound)
            guard e > s else { continue }
            ctx.fill(Path(CGRect(x: x(s), y: inset, width: max(x(e) - x(s), 1), height: H)),
                     with: .color(Theme.band))
        }

        // 基準の線（変化なし）
        var base = Path()
        base.move(to: CGPoint(x: inset, y: yb))
        base.addLine(to: CGPoint(x: inset + W, y: yb))
        ctx.stroke(base, with: .color(Theme.ink.opacity(0.7)), lineWidth: 1.2)
        for (tip, dir) in [(inset, 1.0), (inset + W, -1.0)] {
            var t = Path()
            t.move(to: CGPoint(x: tip, y: yb - 3.6))
            t.addLine(to: CGPoint(x: tip + 4.6 * dir, y: yb))
            t.addLine(to: CGPoint(x: tip, y: yb + 3.6))
            t.closeSubpath()
            ctx.fill(t, with: .color(Theme.ink.opacity(0.7)))
        }

        // 波形は面で塗る。前後6時間のなかを濃く、その外はうすく。
        let nearS = max(window.lowerBound, now - 6)
        let nearE = min(window.upperBound, now + 6)
        func area(_ from: Int, _ to: Int) -> Path? {
            guard to > from else { return nil }
            var top: [CGPoint] = [], bottom: [CGPoint] = []
            for i in from...to {
                guard let v = r[safe: i] ?? nil else { continue }
                let q = dev(v)
                var yA = yb + q, yB = yb - q * mirror
                // 動きのない時間帯でも一本の帯として見えるだけの厚みは残す
                if abs(yA - yB) < 1.8 { yA = yb + 0.9; yB = yb - 0.9 }
                top.append(CGPoint(x: x(i), y: yA))
                bottom.append(CGPoint(x: x(i), y: yB))
            }
            guard top.count > 1 else { return nil }
            var p = Path()
            p.addLines(top)
            p.addLines(bottom.reversed())
            p.closeSubpath()
            return p
        }
        for (from, to, o) in [(window.lowerBound, nearS, 0.28), (nearE, window.upperBound, 0.28), (nearS, nearE, 1.0)] {
            if let p = area(from, to) { ctx.fill(p, with: .color(Theme.ink.opacity(o))) }
        }

        // 前後6時間の境。参考にした波形編集画面の選択範囲にあたる。
        for (idx, dir) in [(nearS, 1.0), (nearE, -1.0)] {
            guard idx > window.lowerBound, idx < window.upperBound else { continue }
            let bx = x(idx)
            var line = Path()
            line.move(to: CGPoint(x: bx, y: inset))
            line.addLine(to: CGPoint(x: bx, y: inset + H))
            ctx.stroke(line, with: .color(Theme.ink.opacity(0.75)), lineWidth: 1.2)
            for yEdge in [inset, inset + H] {
                var t = Path()
                let sign: CGFloat = yEdge == inset ? 1 : -1
                t.move(to: CGPoint(x: bx, y: yEdge))
                t.addLine(to: CGPoint(x: bx + 5 * dir, y: yEdge))
                t.addLine(to: CGPoint(x: bx, y: yEdge + 5 * sign))
                t.closeSubpath()
                ctx.fill(t, with: .color(Theme.ink.opacity(0.75)))
            }
        }

        // いま、またはなぞっている位置
        let at = scrub ?? now
        if window.contains(at), let v = r[safe: at] ?? nil {
            let cx = x(at), cy = yb + dev(v)
            var line = Path()
            line.move(to: CGPoint(x: cx, y: inset))
            line.addLine(to: CGPoint(x: cx, y: inset + H))
            ctx.stroke(line, with: .color(Theme.accent), lineWidth: 1.4)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)),
                     with: .color(Theme.panel))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 3.2, y: cy - 3.2, width: 6.4, height: 6.4)),
                     with: .color(Theme.accent))
        }

        // 目盛りは日によって伸び縮みするので、上下の端が何hPa/時かを添える
        let label = Text(String(format: "±%.1f hPa/h", lim))
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(Theme.inkFaint)
        ctx.draw(label, at: CGPoint(x: inset + 4, y: inset + 8), anchor: .topLeading)
    }
}
