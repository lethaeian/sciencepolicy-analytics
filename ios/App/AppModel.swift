import Foundation
import CoreLocation
import SwiftUI
import UIKit
import WidgetKit

/// 画面の状態と、取得のだんどり。Web 版の start() / load() にあたる。
@MainActor
final class AppModel: NSObject, ObservableObject {

    @Published private(set) var forecast: Forecast?
    @Published private(set) var alarm: Risk.Alarm?
    @Published private(set) var place: String = "…"
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var lastNet: NetOutcome?
    @Published private(set) var busy = false
    @Published var message: String = ""

    /// グラフをなぞっている位置。nil なら現在。
    @Published var scrub: Int?

    /// 画面を消さない。
    @Published var keepAwake = false {
        didSet { UIApplication.shared.isIdleTimerDisabled = keepAwake }
    }

    private let locations = CLLocationManager()
    private var locationWaiters: [CheckedContinuation<CLLocationCoordinate2D, Error>] = []
    private var ticker: Task<Void, Never>?

    /// 取得中の印が立ったままになっても、いつかは必ず抜けられるようにする。
    private var busySince: Date?
    private let busyMax: TimeInterval = 40

    override init() {
        super.init()
        locations.delegate = self
        locations.desiredAccuracy = kCLLocationAccuracyKilometer
        restoreCache()
    }

    // MARK: - 起動と周期

    func onAppear() {
        start()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                guard let self else { return }
                await self.start()
                // 取得が失敗しても、判定文は時計に沿って引き直す
                await MainActor.run { self.recompute() }
            }
        }
    }

    func onDisappear() { ticker?.cancel(); ticker = nil }

    private func restoreCache() {
        if let p = SharedStore.pref { place = p.name }
        if let f = SharedStore.forecast {
            forecast = f
            fetchedAt = SharedStore.fetchedAt
            recompute()
        }
    }

    // MARK: - 取得

    private var isBusy: Bool {
        guard busy else { return false }
        if let s = busySince, Date().timeIntervalSince(s) > busyMax { setBusy(false); return false }
        return true
    }

    private func setBusy(_ on: Bool) {
        busy = on
        busySince = on ? Date() : nil
    }

    func start() {
        guard !isBusy else { return }
        Task { await startAsync() }
    }

    private func startAsync() async {
        let pref = SharedStore.pref
        if let p = pref, p.auto == false {
            await load(name: p.name, lat: p.latitude, lon: p.longitude)
            return
        }
        setBusy(true)
        do {
            let here = try await currentLocation()
            setBusy(false)
            let moved = pref == nil
                || abs((pref?.latitude ?? 0) - here.latitude) > 0.05
                || abs((pref?.longitude ?? 0) - here.longitude) > 0.05
            let name = moved
                ? await WeatherAPI.reverseName(latitude: here.latitude, longitude: here.longitude)
                : (pref?.name ?? "現在地")
            SharedStore.pref = .init(auto: true, name: name, latitude: here.latitude, longitude: here.longitude)
            await load(name: name, lat: here.latitude, lon: here.longitude)
        } catch {
            setBusy(false)
            if let p = pref {
                message = "現在地を取得できないため、前回の地点を表示しています。"
                await load(name: p.name, lat: p.latitude, lon: p.longitude)
            } else {
                message = "現在地を取得できません。地名で検索してください。"
            }
        }
    }

    func use(place p: WeatherAPI.Place) {
        SharedStore.pref = .init(auto: false, name: p.name, latitude: p.latitude, longitude: p.longitude)
        Task { await load(name: p.name, lat: p.latitude, lon: p.longitude) }
    }

    func useCurrentLocation() {
        SharedStore.pref = SharedStore.pref.map { .init(auto: true, name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
        start()
    }

    private func load(name: String, lat: Double, lon: Double) async {
        setBusy(true)
        message = ""
        do {
            let f = try await WeatherAPI.forecast(latitude: lat, longitude: lon)
            forecast = f
            place = name
            fetchedAt = Date()
            scrub = nil
            lastNet = .init(at: Date(), ok: true, why: nil)
            recompute()
            persist(lat: lat, lon: lon)
            setBusy(false)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            setBusy(false)
            let why = (error as? WeatherAPI.Failure)?.errorDescription ?? "原因不明"
            lastNet = .init(at: Date(), ok: false, why: why)
            if forecast != nil {
                message = "更新できませんでした（\(why)）。表示は\(Self.age(fetchedAt))のデータです。"
            } else {
                message = "データを取得できませんでした（\(why)）。通信環境を確認してください。"
            }
        }
    }

    private func recompute() {
        guard let f = forecast else { return }
        alarm = Risk.alarm(f)
    }

    private func persist(lat: Double, lon: Double) {
        guard let f = forecast, let a = alarm else { return }
        SharedStore.forecast = f
        SharedStore.fetchedAt = fetchedAt
        SharedStore.snapshot = .init(
            place: place, latitude: lat, longitude: lon,
            pressure: currentPressure, risk: a.risk,
            level: a.level.key, note: a.note,
            fetchedAt: fetchedAt ?? Date()
        )
    }

    // MARK: - 表示用

    /// なぞっている位置、またはいまの値。
    var shownIndex: Int { scrub ?? forecast?.nowIndex ?? 0 }

    var currentPressure: Double? {
        guard let f = forecast else { return nil }
        if scrub == nil, let c = f.current?.pressure { return c }
        return f.pressure[safe: shownIndex] ?? nil
    }

    var currentTemp: Double? {
        guard let f = forecast else { return nil }
        if scrub == nil, let c = f.current?.temp { return c }
        return f.temp[safe: shownIndex] ?? nil
    }

    var currentHumidity: Double? {
        guard let f = forecast else { return nil }
        if scrub == nil, let c = f.current?.humidity { return c }
        return f.humidity[safe: shownIndex] ?? nil
    }

    /// 3時間前後 12 時間ぶんの窓。
    var window: ClosedRange<Int>? {
        guard let f = forecast else { return nil }
        let s = max(0, f.nowIndex - 12)
        let e = min(f.times.count - 1, f.nowIndex + 12)
        return s <= e ? s...e : nil
    }

    var isStale: Bool {
        guard let at = fetchedAt else { return false }
        return Date().timeIntervalSince(at) > 3 * 60 * 60
    }

    var statusNote: String {
        if isStale { return "\(Self.age(fetchedAt))のデータです。更新してください。" }
        return alarm?.note ?? ""
    }

    var netNote: String {
        guard let n = lastNet else { return "-" }
        if n.ok { return "\(Self.age(n.at)) 成功" }
        return "\(Self.clock(n.at)) 失敗（\(n.why ?? "原因不明")）"
    }

    var localClock: String { Self.clock(Date(), offset: forecast?.utcOffset ?? 0) }

    static func age(_ at: Date?) -> String {
        guard let at else { return "不明" }
        let m = Int(Date().timeIntervalSince(at) / 60)
        if m < 1 { return "たった今" }
        if m < 60 { return "\(m)分前" }
        let h = m / 60
        return h < 24 ? "\(h)時間前" : "\(h / 24)日前"
    }

    static func clock(_ d: Date, offset: Int = 0) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: offset)
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// 窓のなかの時刻を「14:00」で返す。
    func hhmm(_ i: Int) -> String {
        guard let t = forecast?.times[safe: i] else { return "--:--" }
        return Self.clock(t)   // times は地点の現地時刻を UTC として持っている
    }

    // MARK: - 現在地

    private func currentLocation() async throws -> CLLocationCoordinate2D {
        if locations.authorizationStatus == .notDetermined {
            locations.requestWhenInUseAuthorization()
        }
        guard locations.authorizationStatus != .denied,
              locations.authorizationStatus != .restricted else {
            throw CLError(.denied)
        }
        return try await withThrowingTaskGroup(of: CLLocationCoordinate2D.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { c in
                    self.locationWaiters.append(c)
                    self.locations.requestLocation()
                }
            }
            group.addTask {
                // 許可の問いかけが放置されると返ってこない。実時間で打ち切る。
                try await Task.sleep(nanoseconds: 12 * 1_000_000_000)
                throw CLError(.locationUnknown)
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func settleLocation(_ result: Result<CLLocationCoordinate2D, Error>) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        for w in waiters {
            switch result {
            case .success(let c): w.resume(returning: c)
            case .failure(let e): w.resume(throwing: e)
            }
        }
    }
}

extension AppModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let c = locs.last?.coordinate else { return }
        Task { @MainActor in self.settleLocation(.success(c)) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.settleLocation(.failure(error)) }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
                self.start()
            }
        }
    }
}
