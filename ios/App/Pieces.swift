import SwiftUI

/// 3時間おきの気圧。大きな数字をやめたので、いまの気圧はこの列の左端が受け持つ。
/// 先頭だけ実測値、以降は「今からの変化」を符号つきで示す。
struct StripView: View {
    let forecast: Forecast
    let shownPressure: Double?
    var compact = false

    var body: some View {
        let base = forecast.pressure[safe: forecast.nowIndex] ?? nil
        HStack(alignment: .top, spacing: compact ? 4 : 0) {
            ForEach(0..<5, id: \.self) { k in
                let i = forecast.nowIndex + k * 3
                VStack(spacing: compact ? 3 : 5) {
                    Text(k == 0 ? "今" : hour(i))
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(k == 0 ? Theme.ink : Theme.inkFaint)
                    Text(value(k: k, i: i, base: base))
                        .font(.system(size: k == 0 ? (compact ? 15 : 21) : (compact ? 12 : 16),
                                      weight: k == 0 ? .heavy : .bold))
                        .monospacedDigit()
                        .kerning(-0.3)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func hour(_ i: Int) -> String {
        guard let t = forecast.times[safe: i] else { return "--" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "HH"
        return f.string(from: t) + "時"
    }

    private func value(k: Int, i: Int, base: Double?) -> String {
        guard let base, let v = forecast.pressure[safe: i] ?? nil else { return "--" }
        if k == 0 { return String(Int((shownPressure ?? base).rounded())) }
        let diff = v - base
        let r = abs(diff) < 0.05 ? 0 : diff
        let sign = r > 0 ? "+" : (r < 0 ? "-" : "±")
        return sign + String(format: "%.1f", abs(r))
    }
}

/// 気圧のグラフの下に、湿度と気温を左右に並べる。数字が左、推移が右。
struct MetricsView: View {
    let forecast: Forecast
    let window: ClosedRange<Int>
    let humidity: Double?
    let temp: Double?
    let at: Int

    var body: some View {
        HStack(spacing: 14) {
            metric(value: humidity.map { String(Int($0.rounded())) } ?? "--", unit: "%",
                   series: forecast.humidity)
            Divider().overlay(Theme.rule)
            metric(value: temp.map { String(format: "%.1f", $0) } ?? "--", unit: "°C",
                   series: forecast.temp)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private func metric(value: String, unit: String, series: [Double?]) -> some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(size: 21, weight: .heavy)).monospacedDigit().kerning(-0.5)
                Text(unit).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
            }
            .fixedSize()
            Spark(series: series, window: window, now: forecast.nowIndex, at: at)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 細い推移。これまでは実線、この先は点。
private struct Spark: View {
    let series: [Double?]
    let window: ClosedRange<Int>
    let now: Int
    let at: Int

    var body: some View {
        Canvas { ctx, size in
            let vals = window.compactMap { series[safe: $0] ?? nil }
            guard vals.count > 1, window.count > 1 else { return }
            let lo = vals.min()!, hi = vals.max()!
            let span = max(hi - lo, 0.8)
            let pad: CGFloat = 3.5
            func x(_ i: Int) -> CGFloat {
                CGFloat(Double(i - window.lowerBound) / Double(window.count - 1)) * size.width
            }
            func y(_ v: Double) -> CGFloat {
                pad + CGFloat(1 - (v - lo) / span) * (size.height - pad * 2)
            }
            var past = Path(), future = Path()
            var startedPast = false, startedFuture = false
            for i in window {
                guard let v = series[safe: i] ?? nil else { continue }
                let p = CGPoint(x: x(i), y: y(v))
                if i <= now { startedPast ? past.addLine(to: p) : past.move(to: p); startedPast = true }
                if i >= now { startedFuture ? future.addLine(to: p) : future.move(to: p); startedFuture = true }
            }
            ctx.stroke(past, with: .color(Theme.ink), lineWidth: 2)
            ctx.stroke(future, with: .color(Theme.ink.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 3.4]))
            if window.contains(at), let v = series[safe: at] ?? nil {
                let c = CGPoint(x: x(at), y: y(v))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                         with: .color(Theme.bg))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8)),
                         with: .color(Theme.ink))
            }
        }
    }
}
