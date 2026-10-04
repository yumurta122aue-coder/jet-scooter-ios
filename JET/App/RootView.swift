import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var store: RideStore
    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(0)

            ScanScreen()
                .tabItem { Label("Scan", systemImage: "qrcode.viewfinder") }
                .tag(1)

            HistoryScreen()
                .tabItem { Label("Rides", systemImage: "clock.arrow.circlepath") }
                .tag(2)

            ProfileScreen()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(3)

            ToolsScreen()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver.fill") }
                .tag(4)
        }
        .tint(Theme.lime)
        .fullScreenCover(isPresented: isRiding) {
            RideScreen()
        }
        .fullScreenCover(isPresented: hasReceipt) {
            SummaryScreen()
        }
        .alert("hold up", isPresented: alertBinding) {
            Button("got it", role: .cancel) { store.dismissAlert() }
        } message: {
            Text(store.alert ?? "")
        }
        .onAppear(perform: styleTabBar)
    }

    private var isRiding: Binding<Bool> {
        Binding(get: { store.active != nil }, set: { _ in })
    }

    private var hasReceipt: Binding<Bool> {
        // Gated on the ride cover being gone, so two covers never race.
        Binding(
            get: { store.receipt != nil && store.active == nil },
            set: { if !$0 { store.clearReceipt() } }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { store.alert != nil }, set: { if !$0 { store.dismissAlert() } })
    }

    private func styleTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.surface)
        appearance.shadowColor = UIColor(Theme.stroke)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
