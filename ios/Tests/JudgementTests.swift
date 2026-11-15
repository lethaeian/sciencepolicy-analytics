import XCTest
@testable import Kiatsu

/// SwiftUI 版の判定が、Web 版（widget/index.html）と同じ答えを返すかを確かめる。
///
/// Fixtures/judgement.json は Web 版の riskOf / computeAlarm を Node で直接動かして
/// 書き出したもの。240通りの無作為な天候が入っていて、危険度0〜9と4段階すべてを含む。
/// 係数を変えるときは、両方を直してから作り直すこと。
///
///   node scratch/gen-fixture.js   （生成の手順は ios/README.md）
final class JudgementTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Expect: Decodable {
            let risk: Int
            let level: String
            let word: String
            let note: String
        }
        struct Case: Decodable {
            let times: [String]
            let pressure: [Double?]
            let temp: [Double?]
            let humidity: [Double?]
            let nowIndex: Int
            let utcOffset: Int
            let expect: Expect
        }
        let fakeNowEpochMs: Double
        let cases: [Case]
    }

    override func tearDown() {
        Clock.now = { Date() }
        super.tearDown()
    }

    func testMatchesWebImplementation() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "judgement", withExtension: "json"),
            "judgement.json をテストターゲットの Copy Bundle Resources に入れること"
        )
        let fx = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))

        // Web 版が書き出したときと同じ時刻に固定する
        let frozen = Date(timeIntervalSince1970: fx.fakeNowEpochMs / 1000)
        Clock.now = { frozen }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var mismatches: [String] = []

        for (n, c) in fx.cases.enumerated() {
            let times = c.times.compactMap { f.date(from: $0) }
            XCTAssertEqual(times.count, c.times.count, "\(n)件目: 時刻を読めなかった")

            let forecast = Forecast(times: times,
                                    pressure: c.pressure, temp: c.temp, humidity: c.humidity,
                                    nowIndex: c.nowIndex, utcOffset: c.utcOffset, current: nil)
            let a = Risk.alarm(forecast)

            if a.risk != c.expect.risk {
                mismatches.append("\(n)件目 危険度: \(a.risk) ≠ \(c.expect.risk)")
            }
            if a.level.key != c.expect.level {
                mismatches.append("\(n)件目 段階: \(a.level.key) ≠ \(c.expect.level)")
            }
            if a.word != c.expect.word {
                mismatches.append("\(n)件目 見出し: 「\(a.word)」≠「\(c.expect.word)」")
            }
            if a.note != c.expect.note {
                mismatches.append("\(n)件目 注記: 「\(a.note)」≠「\(c.expect.note)」")
            }
        }

        XCTAssertTrue(mismatches.isEmpty,
                      "Web 版と \(mismatches.count) か所ちがう:\n" + mismatches.prefix(20).joined(separator: "\n"))
    }

    /// 要注意の時間帯の切り出しも同じ区切りになるか。
    func testCautionBands() {
        // 10時間かけて下がり続ける。3時間で -2hPa を超える区間が連続する。
        var p: [Double?] = Array(repeating: 1013, count: 6)
        for i in 0..<10 { p.append(1013 - Double(i + 1) * 1.2) }
        p.append(contentsOf: Array(repeating: 1001, count: 6) as [Double?])

        let bands = Risk.cautionBands(p)
        XCTAssertEqual(bands.count, 1, "連続する区間はひと続きにまとめる")
        XCTAssertEqual(bands.first?.lowerBound, 3)
    }

    /// 日付の境で、その日の最高最低を取り違えないか。
    func testDayRangeStaysOnToday() throws {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"

        // 現地時刻 2026-08-12 14:00。前日に 44.4°、当日に 33.7° と 11.3° を置く。
        var times: [Date] = []
        var temp: [Double?] = []
        for day in ["2026-08-11", "2026-08-12"] {
            for h in 0..<24 {
                times.append(f.date(from: String(format: "%@T%02d:00", day, h))!)
                if day == "2026-08-11" && h == 3 { temp.append(44.4) }
                else if day == "2026-08-12" && h == 5 { temp.append(11.3) }
                else if day == "2026-08-12" && h == 14 { temp.append(33.7) }
                else { temp.append(20) }
            }
        }
        let offset = 9 * 3600
        // 現地 14:00 = UTC 05:00
        Clock.now = { f.date(from: "2026-08-12T05:00")! }

        let fc = Forecast(times: times, pressure: temp, temp: temp, humidity: temp,
                          nowIndex: 38, utcOffset: offset, current: nil)
        let day = try XCTUnwrap(fc.dayRange())
        XCTAssertEqual(day.hi, 33.7, "前日の 44.4° を拾ってはいけない")
        XCTAssertEqual(day.lo, 11.3)
    }
}
