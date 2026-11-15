import Foundation

/// 本体とウィジェットで分け合う置き場。
/// App Group を有効にすると、ウィジェットが本体の地点と最後の中身を読める。
enum SharedStore {

    /// ここを自分の App Group に書き換える（Xcode の Signing & Capabilities で作る名前と揃える）。
    static let appGroup = "group.com.example.kiatsu"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // MARK: - 地点

    struct Pref: Codable, Equatable {
        var auto: Bool
        var name: String
        var latitude: Double
        var longitude: Double
    }

    static var pref: Pref? {
        get { read("pref") }
        set { write("pref", newValue) }
    }

    // MARK: - 最後に取れた中身

    static var snapshot: Snapshot? {
        get { read("snapshot") }
        set { write("snapshot", newValue) }
    }

    /// 取得そのものを控えておき、起動直後でも何か出せるようにする。
    static var forecast: Forecast? {
        get { read("forecast") }
        set { write("forecast", newValue) }
    }

    static var fetchedAt: Date? {
        get { read("fetchedAt") }
        set { write("fetchedAt", newValue) }
    }

    // MARK: -

    private static func read<T: Decodable>(_ key: String) -> T? {
        guard let d = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    private static func write<T: Encodable>(_ key: String, _ value: T?) {
        guard let value, let d = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key); return
        }
        defaults.set(d, forKey: key)
    }
}
