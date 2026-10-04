import SwiftUI

@main
struct JETApp: App {
    @StateObject private var store = RideStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.lime)
        }
    }
}
