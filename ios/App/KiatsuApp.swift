import SwiftUI

@main
struct KiatsuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(nil)   // 端末の明暗にしたがう
        }
    }
}
