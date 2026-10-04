import SwiftUI

struct RideScreen: View {
    @EnvironmentObject private var store: RideStore
    @State private var confirmEnd = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                meter
                Spacer(minLength: 12)
                stats
                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .alert("end the ride?", isPresented: $confirmEnd) {
            Button("end ride", role: .destructive) { store.endRide() }
            Button("keep riding", role: .cancel) {}
        } message: {
            Text("you'll be charged \(store.liveCost.money) for \(store.elapsed.clock).")
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.lime)
                .frame(width: 8, height: 8)
                .shadow(color: Theme.lime, radius: 6)

            Text("ride in progress")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.lime)
                .textCase(.uppercase)

            Spacer()

            Text(store.active?.scooterID ?? "")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }

    private var meter: some View {
        VStack(spacing: 6) {
            Text(store.elapsed.clock)
                .font(.system(size: 78, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.text)

            Text(store.liveCost.money)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.lime)

            Text(store.liveScooter.map { "\($0.pricePerMinute.money)/min · unlock \($0.unlockFee.money)" } ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textDim)
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            stat(icon: "point.topleft.down.curvedto.point.bottomright.up",
                 value: store.distanceKm.oneDecimal, unit: "km")
            stat(icon: "battery.75",
                 value: "\(store.unlock.vehicleBattery ?? store.liveScooter?.battery ?? 0)", unit: "%")
            stat(icon: "antenna.radiowaves.left.and.right",
                 value: "\(store.unlock.signalStrength ?? 0)", unit: "dBm")
        }
    }

    private func stat(icon: String, value: String, unit: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.lime)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("link held open by heartbeat · drops if you walk away")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.textDim)

            Button("End ride", action: { confirmEnd = true })
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}
