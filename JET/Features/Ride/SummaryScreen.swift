import SwiftUI
import MapKit

struct SummaryScreen: View {
    @EnvironmentObject private var store: RideStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let ride = store.receipt {
                ScrollView {
                    VStack(spacing: 18) {
                        header(ride)
                        routeMap
                        breakdown(ride)
                        footer(ride)
                    }
                    .padding(20)
                }
            }
        }
    }

    private func header(_ ride: Ride) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.limeSoft).frame(width: 74, height: 74)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Theme.lime)
            }
            .padding(.top, 30)

            Text("ride complete")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)

            Text(ride.cost.money)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(Theme.lime)
        }
    }

    private var routeMap: some View {
        Map(initialPosition: .region(
            MKCoordinateRegion(center: RideStore.demoCenter,
                               span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
        )) {
            if store.track.count > 1 {
                MapPolyline(coordinates: store.track.map(\.coordinate))
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .allowsHitTesting(false)
    }

    private func breakdown(_ ride: Ride) -> some View {
        Card {
            VStack(spacing: 12) {
                row("scooter", ride.scooterID, mono: true)
                row("duration", ride.duration.clock)
                row("distance", "\(String(format: "%.2f", ride.distanceMeters / 1000)) km")
                row("average speed", averageSpeed(ride))
                Divider().overlay(Theme.stroke)

                if let scooter = Scooter.find(ride.scooterID) {
                    row("unlock fee", scooter.unlockFee.money)
                    row("time charge", "\(scooter.pricePerMinute.money) × \(String(format: "%.1f", ride.duration / 60)) min")
                }
                Divider().overlay(Theme.stroke)
                row("charged to balance", ride.cost.money, strong: true)
            }
        }
    }

    private func footer(_ ride: Ride) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("new balance")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text(store.balance.money)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 4)

            Button("Done") {
                store.clearReceipt()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.bottom, 30)
    }

    private func averageSpeed(_ ride: Ride) -> String {
        let hours = ride.duration / 3600
        guard hours > 0.001 else { return "—" }
        return String(format: "%.1f km/h", (ride.distanceMeters / 1000) / hours)
    }

    private func row(_ label: String, _ value: String, mono: Bool = false, strong: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(strong ? Theme.text : Theme.textDim)
            Spacer()
            Text(value)
                .font(.system(size: strong ? 17 : 14,
                              weight: strong ? .bold : .semibold,
                              design: mono ? .monospaced : .rounded))
                .foregroundStyle(strong ? Theme.lime : Theme.text)
                .monospacedDigit()
        }
    }
}

private extension TrackPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
