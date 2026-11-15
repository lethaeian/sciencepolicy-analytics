import Foundation

/// 気象データの取得。Web 版の fetchWeather / reverseName / geocodeSearch にあたる。
///
/// Web 版でぶつかった不具合をそのまま踏まえている。
///   ・応答が返らないまま止まることがあるので、実時間で必ず打ち切る。
///   ・失敗の種類を区別して、画面に理由を出せるようにする。
enum WeatherAPI {

    /// 1回の通信を待つ上限。
    static let timeout: TimeInterval = 15

    enum Failure: LocalizedError {
        case timedOut
        case http(Int)
        case offline
        case malformed

        /// 画面に出す短い理由。
        var errorDescription: String? {
            switch self {
            case .timedOut:      return "応答がありません"
            case .http(let s):   return "気象サーバーの応答 \(s)"
            case .offline:       return "接続できません"
            case .malformed:     return "応答を読み取れません"
            }
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral        // 古い応答を使い回さない
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private static func get(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw Failure.offline }
            guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
            return data
        } catch let e as Failure {
            throw e
        } catch let e as URLError {
            throw e.code == .timedOut ? Failure.timedOut : Failure.offline
        } catch {
            throw Failure.offline
        }
    }

    // MARK: - 予報

    static func forecast(latitude: Double, longitude: Double) async throws -> Forecast {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "hourly", value: "temperature_2m,relative_humidity_2m,pressure_msl"),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,pressure_msl"),
            .init(name: "past_days", value: "1"),
            .init(name: "forecast_days", value: "2"),
            .init(name: "timezone", value: "auto")
        ]
        let raw = try await get(c.url!)

        struct Payload: Decodable {
            struct Hourly: Decodable {
                let time: [String]
                let pressure_msl: [Double?]
                let temperature_2m: [Double?]
                let relative_humidity_2m: [Double?]
            }
            struct Current: Decodable {
                let pressure_msl: Double?
                let temperature_2m: Double?
                let relative_humidity_2m: Double?
            }
            let utc_offset_seconds: Int?
            let hourly: Hourly
            let current: Current?
        }

        guard let p = try? JSONDecoder().decode(Payload.self, from: raw) else { throw Failure.malformed }

        // "2026-08-12T14:00" は地点の現地時刻。UTC として読み、表示でもそのまま使う。
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let times = p.hourly.time.compactMap { f.date(from: $0) }
        guard times.count == p.hourly.time.count, !times.isEmpty else { throw Failure.malformed }

        let offset = p.utc_offset_seconds ?? 0
        return Forecast(
            times: times,
            pressure: p.hourly.pressure_msl,
            temp: p.hourly.temperature_2m,
            humidity: p.hourly.relative_humidity_2m,
            nowIndex: nowIndex(times: times, utcOffset: offset),
            utcOffset: offset,
            current: p.current.map {
                .init(pressure: $0.pressure_msl, temp: $0.temperature_2m, humidity: $0.relative_humidity_2m)
            }
        )
    }

    /// 毎時の刻みと「現在値」の時刻は一致しない。地点の現地時刻から直接求める。
    static func nowIndex(times: [Date], utcOffset: Int) -> Int {
        let now = Clock.now().addingTimeInterval(TimeInterval(utcOffset))
        var best = 0
        for (i, t) in times.enumerated() {
            if t <= now { best = i } else { break }
        }
        return best
    }

    // MARK: - 地名

    static func reverseName(latitude: Double, longitude: Double) async -> String {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "count", value: "1"),
            .init(name: "language", value: "ja"),
            .init(name: "format", value: "json")
        ]
        struct R: Decodable { struct Item: Decodable { let name: String }; let results: [Item]? }
        guard let data = try? await get(c.url!),
              let r = try? JSONDecoder().decode(R.self, from: data),
              let first = r.results?.first else { return "現在地" }
        return first.name
    }

    struct Place: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let admin: String?
        let latitude: Double
        let longitude: Double
        var label: String { admin.map { "\(name) · \($0)" } ?? name }
    }

    static func search(_ query: String) async -> [Place] {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            .init(name: "name", value: query),
            .init(name: "count", value: "8"),
            .init(name: "language", value: "ja"),
            .init(name: "format", value: "json")
        ]
        struct R: Decodable {
            struct Item: Decodable {
                let name: String
                let admin1: String?
                let latitude: Double
                let longitude: Double
            }
            let results: [Item]?
        }
        guard let data = try? await get(c.url!),
              let r = try? JSONDecoder().decode(R.self, from: data) else { return [] }
        return (r.results ?? []).map {
            Place(name: $0.name, admin: $0.admin1, latitude: $0.latitude, longitude: $0.longitude)
        }
    }
}
