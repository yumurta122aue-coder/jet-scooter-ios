import SwiftUI

struct HistoryScreen: View {
    @EnvironmentObject private var store: RideStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if store.history.isEmpty {
                    empty
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            totals
                            ForEach(store.history) { ride in
                                row(ride)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("your rides")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.bg, for: .navigationBar)
        }
    }

    private var totals: some View {
        HStack(spacing: 12) {
            tile(value: "\(store.history.count)", label: "rides")
            tile(value: String(format: "%.1f", store.history.reduce(0) { $0 + $1.distanceMeters } / 1000), label: "km")
            tile(value: store.history.reduce(0) { $0 + $1.cost }.money, label: "spent")
        }
    }

    private func tile(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.lime)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .textCase(.uppercase)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private func row(_ ride: Ride) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.limeSoft).frame(width: 46, height: 46)
                Image(systemName: "scooter")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.lime)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ride.scooterID)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                Text("\(ride.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(ride.duration.clock) · \(String(format: "%.2f", ride.distanceMeters / 1000)) km")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }

            Spacer()

            Text(ride.cost.money)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.textDim)
            Text("no rides yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("scan a scooter and your receipts land here")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textDim)
        }
    }
}
