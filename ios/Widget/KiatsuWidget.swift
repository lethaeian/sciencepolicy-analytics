import WidgetKit
import SwiftUI

/// ロック画面とホーム画面のウィジェット。
/// 本体が保存した地点で自分でも取りにいき、だめなら本体の控えを出す。
struct Entry: TimelineEntry {
    let date: Date
    let risk: Int
    let pressure: Double?
    let place: String
    let stale: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), risk: 3, pressure: 1009, place: "—", stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(current() ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            var entry = current() ?? placeholder(in: context)
            if let p = SharedStore.pref,
               let f = try? await WeatherAPI.forecast(latitude: p.latitude, longitude: p.longitude) {
                SharedStore.forecast = f
                SharedStore.fetchedAt = Date()
                entry = Entry(date: Date(),
                              risk: Risk.score(f),
                              pressure: f.current?.pressure ?? (f.pressure[safe: f.nowIndex] ?? nil),
                              place: p.name,
                              stale: false)
            }
            // 次は30分後に見にくる。実際の間隔は端末側が決める。
            let next = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func current() -> Entry? {
        guard let s = SharedStore.snapshot else { return nil }
        return Entry(date: s.fetchedAt, risk: s.risk, pressure: s.pressure, place: s.place,
                     stale: Date().timeIntervalSince(s.fetchedAt) > 3 * 60 * 60)
    }
}

struct KiatsuWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var body: some View {
        switch family {
        case .accessoryCircular:
            RiskCircle(risk: entry.risk, rows: 13, ink: .primary, dim: 0.25, animated: false)
                .padding(2)
        case .accessoryInline:
            Text("\(pressureText) · 目安 \(entry.risk)/9")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                RiskCircle(risk: entry.risk, rows: 13, ink: .primary, dim: 0.25, animated: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pressureText).font(.headline)
                    Text("目安 \(entry.risk)/9").font(.caption2)
                    Text(entry.place).font(.caption2).foregroundStyle(.secondary)
                }
            }
        default:
            VStack(spacing: 8) {
                RiskCircle(risk: entry.risk, rows: 19, animated: false)
                Text(pressureText).font(.system(size: 17, weight: .heavy)).monospacedDigit()
            }
            .padding(10)
            .containerBackground(Theme.bg, for: .widget)
        }
    }

    private var pressureText: String {
        entry.pressure.map { "\(Int($0.rounded()))hPa" } ?? "--"
    }
}

@main
struct KiatsuWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KiatsuWidget", provider: Provider()) { entry in
            KiatsuWidgetView(entry: entry)
        }
        .configurationDisplayName("気圧・体調")
        .description("気圧の変化からみた体調の目安。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}
