import Foundation

/// いまが何時か。テストで固定できるよう、1か所にまとめる。
enum Clock {
    static var now: () -> Date = { Date() }
}

/// 気象データ。Web 版 (widget/index.html) の state.data にあたる。
/// 時刻は観測地点の現地時刻で並んでいる。
struct Forecast: Codable, Equatable {
    var times: [Date]
    var pressure: [Double?]
    var temp: [Double?]
    var humidity: [Double?]
    var nowIndex: Int
    var utcOffset: Int
    /// 毎時の値とは別に届く「現在値」。毎時の刻みより短い間隔で動く。
    var current: Current?

    struct Current: Codable, Equatable {
        var pressure: Double?
        var temp: Double?
        var humidity: Double?
    }

    /// 取得地点の現地時刻。
    func localNow() -> Date { Clock.now().addingTimeInterval(TimeInterval(utcOffset)) }

    /// その地点の「今日」の最高・最低気温。
    ///
    /// times は「地点の現地時刻を UTC として読んだもの」なので、
    /// 比べる相手（localNow）も同じ読み方で揃える。ここで時差を二重に
    /// 足すと、日付の境でちょうど1日ぶんずれる。
    func dayRange() -> (hi: Double, lo: Double)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = cal.startOfDay(for: localNow())
        var hi: Double?, lo: Double?
        for (i, t) in times.enumerated() {
            guard cal.startOfDay(for: t) == today,
                  let v = temp[safe: i] ?? nil else { continue }
            if hi == nil || v > hi! { hi = v }
            if lo == nil || v < lo! { lo = v }
        }
        guard let h = hi, let l = lo else { return nil }
        return (h, l)
    }

    /// i の n 時間前からの変化。足りなければ nil。
    func back(_ a: [Double?], _ i: Int, _ n: Int) -> Double? {
        let j = i - n
        guard j >= 0, i < a.count, let x = a[safe: j] ?? nil, let y = a[safe: i] ?? nil else { return nil }
        return y - x
    }

    /// i から n 時間先への変化。
    func ahead(_ a: [Double?], _ i: Int, _ n: Int) -> Double? {
        let j = i + n
        guard j < a.count, let x = a[safe: i] ?? nil, let y = a[safe: j] ?? nil else { return nil }
        return y - x
    }
}

/// 画面に残す最後の通信の結果。Web 版の netNote にあたる。
struct NetOutcome: Codable, Equatable {
    var at: Date
    var ok: Bool
    var why: String?
}

/// ウィジェットと本体で受け渡す、最小限の控え。
struct Snapshot: Codable, Equatable {
    var place: String
    var latitude: Double
    var longitude: Double
    var pressure: Double?
    var risk: Int
    var level: String
    var note: String
    var fetchedAt: Date
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
