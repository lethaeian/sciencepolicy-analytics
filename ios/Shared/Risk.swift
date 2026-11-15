import Foundation

/// 体調の目安。Web 版 (widget/index.html) の riskOf / computeAlarm をそのまま移したもの。
/// 係数を変えるときは Web 版と揃えること。
enum Risk {

    enum Level: Int, Comparable {
        case good = 0, warning, serious, critical
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        /// Web 版と同じ綴り。突き合わせに使う。
        var key: String {
            switch self {
            case .good: return "good"
            case .warning: return "warning"
            case .serious: return "serious"
            case .critical: return "critical"
            }
        }
        var word: String {
            switch self {
            case .good: return "問題なし"
            case .warning: return "注意"
            case .serious: return "警戒"
            case .critical: return "厳重警戒"
            }
        }
    }

    struct Threshold { let past3: Double; let past6: Double; let future6: Double }
    static let warning  = Threshold(past3: -2, past6: -3, future6: -3)
    static let serious  = Threshold(past3: -4, past6: -6, future6: -5)
    static let critical = Threshold(past3: -6, past6: -9, future6: -8)

    struct Note { let kind: String; let text: String }

    struct Alarm {
        var level: Level
        var word: String
        var note: String
        var risk: Int          // 0〜9
        var notes: [Note]
        var d3: Double?
        var d6: Double?
        var f6: Double?
        var hum: Double?
        var temp: Double?
    }

    // MARK: - 0〜9 の目盛り

    /// 気圧の下がり方を主軸に、湿度と気温を上乗せする。
    ///   気圧 … 0.7hPa/3時間 ごとに1点。6時間と予報も同じ重みに揃えて最大を採る
    ///   湿度 … 62%を超えたぶんを9で割る。蒸し暑さは別に上乗せ（最大4.5点）
    ///   気温 … 下がり幅と、極端な暑さ寒さ（最大1.5点）
    static func score(_ d: Forecast) -> Int {
        let i = d.nowIndex
        func fall(_ x: Double?) -> Double { max(0, -(x ?? 0)) }

        let sp = max(
            fall(d.back(d.pressure, i, 3)) / 0.7,
            fall(d.back(d.pressure, i, 6)) / 1.25,
            fall(d.ahead(d.pressure, i, 6)) / 1.5
        )

        let hum = d.humidity[safe: i] ?? nil
        let tp  = d.temp[safe: i] ?? nil
        var sh = 0.0
        if let h = hum {
            if h > 62 { sh += (h - 62) / 9 }
            if h <= 32 { sh += (32 - h) / 11 }
            if h >= 72, let t = tp, t >= 25 { sh += 1.0 }
        }
        sh = min(4.5, sh)

        var st = fall(d.back(d.temp, i, 3)) / 4 + fall(d.ahead(d.temp, i, 6)) / 6
        if let t = tp, t <= 5 || t >= 31 { st += 0.8 }
        st = min(1.5, st)

        return max(0, min(9, Int((sp + sh + st).rounded())))
    }

    // MARK: - 見出しと注記

    private static func level(_ delta: Double?, _ pick: (Threshold) -> Double) -> Level {
        guard let d = delta else { return .good }
        if d <= pick(critical) { return .critical }
        if d <= pick(serious)  { return .serious }
        if d <= pick(warning)  { return .warning }
        return .good
    }

    private static func pastPhrase(_ r: Double?) -> String {
        guard let r else { return "確認中" }
        if r <= -6 { return "急降下しています" }
        if r <= -4 { return "大きく下降中" }
        if r <= -2 { return "下降しています" }
        if r <= -0.8 { return "ゆるやかに低下" }
        if r < 0.8 { return "落ち着いています" }
        if r < 2.5 { return "ゆるやかに回復" }
        return "上昇しています"
    }

    private static func futurePhrase(_ r: Double?) -> String {
        guard let r else { return "確認中" }
        if r <= -8 { return "まもなく急降下" }
        if r <= -5 { return "まもなく大きく下降" }
        return "これから下がります"
    }

    /// 気圧ではなく湿度・気温で針が振れたときの言い方。
    private static let nonPressureWord: [String: String] = [
        "muggy":    "蒸し暑さが重なっています",
        "humid":    "湿度が高い状態です",
        "dry":      "空気が乾いています",
        "hot":      "気温が高い状態です",
        "cold":     "気温が低い状態です",
        "tempFall": "気温が下がっています",
        "tempRise": "気温が上がっています",
        "coolDown": "この先気温が下がります",
        "swing":    "気温差が大きい一日です"
    ]

    static func weatherNotes(_ d: Forecast) -> [Note] {
        let i = d.nowIndex
        let hum = d.humidity[safe: i] ?? nil
        let tp  = d.temp[safe: i] ?? nil
        let dT3 = d.back(d.temp, i, 3)
        let fT6 = d.ahead(d.temp, i, 6)
        var out: [Note] = []

        if let x = dT3, x <= -4 { out.append(.init(kind: "tempFall", text: String(format: "3時間で気温 %.1f°", x))) }
        if let x = dT3, x >= 5  { out.append(.init(kind: "tempRise", text: String(format: "3時間で気温 +%.1f°", x))) }

        if let h = hum, let t = tp, h >= 80, t >= 24 {
            out.append(.init(kind: "muggy", text: "湿度 \(Int(h.rounded()))%"))
        } else if let h = hum, h >= 85 {
            out.append(.init(kind: "humid", text: "湿度 \(Int(h.rounded()))%"))
        } else if let h = hum, h <= 30 {
            out.append(.init(kind: "dry", text: "湿度 \(Int(h.rounded()))%"))
        }

        if let day = d.dayRange(), day.hi - day.lo >= 10 {
            out.append(.init(kind: "swing", text: "気温差 \(Int((day.hi - day.lo).rounded()))°"))
        }
        if let x = fT6, x <= -5 { out.append(.init(kind: "coolDown", text: String(format: "この先6時間 %.1f°", x))) }
        if let t = tp, t <= 5  { out.append(.init(kind: "cold", text: String(format: "気温 %.1f°", t))) }
        if let t = tp, t >= 30 { out.append(.init(kind: "hot",  text: String(format: "気温 %.1f°", t))) }
        return out
    }

    static func alarm(_ d: Forecast) -> Alarm {
        let i = d.nowIndex
        let d3 = d.back(d.pressure, i, 3)
        let d6 = d.back(d.pressure, i, 6)
        let f6 = d.ahead(d.pressure, i, 6)

        let lv = [level(d3) { $0.past3 }, level(d6) { $0.past6 }, level(f6) { $0.future6 }]
        var lvl = lv.max() ?? .good

        // 先の下降のほうが重いときは、これから起きることを見出しにする
        let futureLeads = lv[2] > max(lv[0], lv[1])
        var word = futureLeads ? futurePhrase(f6) : pastPhrase(d3)

        let notes = weatherNotes(d)
        let pressureLevel = lvl          // 注記の組み立ては気圧の段階で決める

        // 気圧が穏やかでも湿度や気温で針が振れる。目盛りと色・言葉が
        // 食い違わないよう、段階を引き上げる。
        let risk = score(d)
        let byRisk: Level = risk >= 7 ? .critical : risk >= 5 ? .serious : risk >= 3 ? .warning : .good
        if byRisk > lvl {
            lvl = byRisk
            word = nonPressureWord[notes.first?.kind ?? ""] ?? "気圧以外の負荷があります"
        }

        var lines: [String] = []
        if pressureLevel != .good {
            var c: [(Double, String)] = []
            if let x = d3, lv[0] > .good { c.append((x, String(format: "3時間 %.1fhPa", x))) }
            if let x = d6, lv[1] > .good { c.append((x, String(format: "6時間 %.1fhPa", x))) }
            if let x = f6, lv[2] > .good { c.append((x, String(format: "この先6時間 %.1fhPa", x))) }
            c.sort { $0.0 < $1.0 }
            if let first = c.first { lines.append(first.1) }
            if let n = notes.first { lines.append(n.text) }
        } else {
            lines.append(contentsOf: notes.prefix(2).map(\.text))
        }

        return Alarm(level: lvl, word: word, note: lines.joined(separator: " · "),
                     risk: risk, notes: notes, d3: d3, d6: d6, f6: f6,
                     hum: d.humidity[safe: i] ?? nil, temp: d.temp[safe: i] ?? nil)
    }

    // MARK: - 要注意の時間帯

    /// 3時間あたりの下がり幅が注意水準に達する区間。連続する区間はひと続きにする。
    static func cautionBands(_ pressure: [Double?]) -> [ClosedRange<Int>] {
        var bands: [ClosedRange<Int>] = []
        var start: Int?
        var end = 0
        var i = 0
        while i + 3 < pressure.count {
            defer { i += 1 }
            guard let a = pressure[safe: i] ?? nil, let b = pressure[safe: i + 3] ?? nil else { continue }
            if b - a <= warning.past3 {
                if start == nil { start = i }
                end = i + 3
            } else if let s = start {
                bands.append(s...end); start = nil
            }
        }
        if let s = start { bands.append(s...end) }
        return bands
    }
}
