import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @Environment(\.verticalSizeClass) private var vSize
    @State private var showSearch = false
    @State private var showAbout = false

    private var landscape: Bool { vSize == .compact }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Group {
                if landscape { wide } else { tall }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .foregroundStyle(Theme.ink)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .sheet(isPresented: $showSearch) { SearchSheet(model: model) }
        .sheet(isPresented: $showAbout) { AboutSheet(model: model) }
    }

    // MARK: - 縦向き

    private var tall: some View {
        VStack(spacing: 0) {
            RiskCircle(risk: model.alarm?.risk ?? 0)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, -20)      // 画面の幅いっぱいに近づける
            note.padding(.top, 9)
            minmax.padding(.top, 5)
            strip.padding(.top, 9)
            plot.padding(.top, 8)
            metrics.padding(.top, 8)
            footRow.padding(.top, 10)
            message
            aboutLink.padding(.top, 4)
        }
    }

    // MARK: - 横向き

    private var wide: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 10) {
                RiskCircle(risk: model.alarm?.risk ?? 0)
                minmax
            }
            .frame(maxWidth: 380)

            VStack(spacing: 0) {
                note
                strip.padding(.top, 8)
                plot.padding(.top, 8).frame(maxHeight: .infinity)
                metrics.padding(.top, 8)
                aboutLink.padding(.top, 8)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 14) {
                Spacer(minLength: 0)
                refreshButton
                Text(model.localClock)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Theme.inkSoft)
                wakeButton
                searchButton
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 部品

    @ViewBuilder private var note: some View {
        if !model.statusNote.isEmpty {
            Text(model.statusNote)
                .font(.system(size: 13)).monospacedDigit()
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var minmax: some View {
        HStack(spacing: 16) {
            if let day = model.forecast?.dayRange() {
                pair("max", day.hi)
                pair("min", day.lo)
            } else {
                pair("max", nil); pair("min", nil)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pair(_ key: String, _ v: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(key.uppercased())
                .font(.system(size: 9, weight: .bold)).kerning(1)
                .foregroundStyle(Theme.inkFaint)
            Text(v.map { String(format: "%.1f", $0) } ?? "--")
                .font(.system(size: 15, weight: .bold)).monospacedDigit()
            Text("°").font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
        }
    }

    @ViewBuilder private var strip: some View {
        if let f = model.forecast {
            StripView(forecast: f, shownPressure: model.currentPressure, compact: landscape)
        }
    }

    @ViewBuilder private var plot: some View {
        if let f = model.forecast, let w = model.window {
            VStack(spacing: 6) {
                PressureWave(forecast: f, window: w, scrub: $model.scrub)
                    .frame(minHeight: landscape ? 90 : 110)
                HStack {
                    Text("−12h")
                    Spacer()
                    Text(scrubLabel).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text("+12h")
                }
                .font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private var scrubLabel: String {
        guard let i = model.scrub else { return "現在" }
        let p = model.currentPressure.map { "  \(Int($0.rounded()))hPa" } ?? ""
        return model.hhmm(i) + p
    }

    @ViewBuilder private var metrics: some View {
        if let f = model.forecast, let w = model.window {
            MetricsView(forecast: f, window: w,
                        humidity: model.currentHumidity, temp: model.currentTemp,
                        at: model.shownIndex)
        }
    }

    private var footRow: some View {
        HStack(spacing: 12) {
            refreshButton
            Text(model.localClock)
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
            wakeButton
            searchButton
        }
    }

    private var refreshButton: some View {
        Button { model.start() } label: {
            Circle().fill(Theme.knob)
                .frame(width: 44, height: 44)
                .overlay(Circle().fill(Theme.accent).frame(width: 18, height: 18))
                .opacity(model.busy ? 0.45 : 1)
        }
        .accessibilityLabel(model.busy ? "更新中" : "更新")
        .animation(model.busy ? .easeInOut(duration: 1).repeatForever() : .default, value: model.busy)
    }

    private var wakeButton: some View {
        glyph(system: "sun.max", on: model.keepAwake, label: "画面を消さない") {
            model.keepAwake.toggle()
        }
    }

    private var searchButton: some View {
        glyph(system: "magnifyingglass", on: false, label: "地名を変える") {
            showSearch = true
        }
    }

    private func glyph(system: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? Theme.ink : .clear)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
                .overlay(Image(systemName: system).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(on ? Theme.bg : Theme.ink))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var message: some View {
        if !model.message.isEmpty {
            Text(model.message)
                .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }

    private var aboutLink: some View {
        Button { showAbout = true } label: {
            Text("体調の目安について")
                .font(.system(size: 10)).kerning(1.4)
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 地名の検索

struct SearchSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [WeatherAPI.Place] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                Button("現在地に戻す") {
                    model.useCurrentLocation(); dismiss()
                }
                ForEach(results) { p in
                    Button(p.label) { model.use(place: p); dismiss() }
                }
                if searching { ProgressView() }
            }
            .searchable(text: $query, prompt: "地名で検索")
            .onChange(of: query) { _, q in
                Task {
                    guard q.trimmingCharacters(in: .whitespaces).count >= 1 else { results = []; return }
                    searching = true
                    try? await Task.sleep(nanoseconds: 300_000_000)    // 打ちながらの連打を抑える
                    guard q == query else { return }
                    results = await WeatherAPI.search(q)
                    searching = false
                }
            }
            .navigationTitle("地点")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - ことわり

struct AboutSheet: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("気圧・気温・湿度の変化にもとづく一般的な目安です。医学的な診断ではありません。体調がすぐれないときは無理をせず、症状が続く場合は医療機関にご相談ください。")
                        .font(.footnote)
                }
                Section("出典") {
                    Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                }
                Section("状態") {
                    LabeledContent("地点", value: model.place)
                    LabeledContent("最後の通信", value: model.netNote)
                }
            }
            .navigationTitle("体調の目安について")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
