import SwiftUI

/// Web 版と同じ配色。地は一色、図は黒一色、差し色は赤だけ。
enum Theme {
    static let bg       = Color("Bg")
    static let ink      = Color("Ink")
    static let accent   = Color("Accent")
    static let panel    = Color("Panel")
    static let knob     = Color("Knob")

    static var inkSoft:  Color { ink.opacity(0.62) }
    static var inkFaint: Color { ink.opacity(0.42) }
    static var rule:     Color { ink.opacity(0.16) }
    static var band:     Color { ink.opacity(0.085) }
    /// 未点灯の目盛り
    static let dim = 0.17
}

/// 横線を積んだ円。下から点灯し、満ちるほど負荷が大きい。
/// 本体とウィジェットの両方で使う。
struct RiskCircle: View {
    var risk: Int                  // 0〜9
    var rows: Int = 27
    var ink: Color = Theme.ink
    var dim: Double = Theme.dim
    /// 点灯の変化をなめらかに見せる。ウィジェットでは効かないので false。
    var animated: Bool = true

    private var lit: Int { Int((Double(rows) * Double(risk + 1) / 10).rounded()) }

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let s = side / 200                      // Web 版と同じ 200 の座標系
            let ox = (size.width  - side) / 2
            let oy = (size.height - side) / 2
            let cx = 100.0, cy = 100.0, r = 92.0, gap = 7.0
            let step = (r * 1.91) / Double(rows - 1)

            for k in 0..<rows {
                let dy = (Double(k) - Double(rows - 1) / 2) * step
                let hw = (r * r - dy * dy > 0) ? (r * r - dy * dy).squareRoot() : 0
                guard hw > gap + 1.5 else { continue }
                let y = cy + dy
                let on = k >= rows - lit
                let w = step * 0.62

                for seg in [(cx - hw, cx - gap), (cx + gap, cx + hw)] {
                    let rect = CGRect(x: ox + seg.0 * s, y: oy + (y - w / 2) * s,
                                      width: (seg.1 - seg.0) * s, height: w * s)
                    ctx.fill(Path(rect), with: .color(ink.opacity(on ? 1 : dim)))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(animated ? .easeOut(duration: 0.45) : nil, value: risk)
        .accessibilityLabel("体調の目安 10段階中 \(risk)")
    }
}
