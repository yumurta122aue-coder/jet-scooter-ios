import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject private var store: RideStore

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: RideStore.demoCenter,
                           span: MKCoordinateSpan(latitudeDelta: 0.011, longitudeDelta: 0.011))
    )
    @State private var selected: Scooter?
    @State private var showUnlock = false

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                ForEach(store.scooters) { scooter in
                    Annotation(scooter.id, coordinate: scooter.coordinate) {
                        ScooterPin(scooter: scooter, selected: selected?.id == scooter.id)
                            .onTapGesture { select(scooter) }
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls { MapCompass() }
            .ignoresSafeArea(edges: .top)

            header

            VStack {
                Spacer()
                if let scooter = selected {
                    ScooterCard(scooter: scooter,
                                onUnlock: { showUnlock = true },
                                onClose: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selected = nil } })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showUnlock) {
            if let scooter = selected {
                UnlockSheet(scooter: scooter)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: store.active?.id) { _, newValue in
            if newValue != nil { showUnlock = false; selected = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("JET")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.lime)
                Text("\(store.scooters.count) scooters nearby")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.balance.money)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("balance")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.surface.opacity(0.92)))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func select(_ scooter: Scooter) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selected = scooter
        }
        camera = .region(MKCoordinateRegion(
            center: scooter.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        ))
    }
}

struct ScooterPin: View {
    let scooter: Scooter
    let selected: Bool

    private var tint: Color {
        switch scooter.batteryTint {
        case "high": return Theme.lime
        case "mid":  return Theme.amber
        default:     return Theme.danger
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(selected ? Theme.lime : Theme.surface)
                    .frame(width: selected ? 46 : 38, height: selected ? 46 : 38)
                    .overlay(Circle().stroke(selected ? Theme.bg : tint, lineWidth: 2.5))
                    .shadow(color: tint.opacity(0.45), radius: selected ? 12 : 6)

                Image(systemName: "scooter")
                    .font(.system(size: selected ? 21 : 17, weight: .bold))
                    .foregroundStyle(selected ? Theme.bg : tint)
            }
            Triangle()
                .fill(selected ? Theme.lime : Theme.surface)
                .frame(width: 10, height: 6)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct ScooterCard: View {
    let scooter: Scooter
    let onUnlock: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scooter.id)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("ready to ride")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.lime)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .padding(9)
                        .background(Circle().fill(Theme.surfaceHi))
                }
            }

            HStack(spacing: 10) {
                metric(icon: "battery.75", value: "\(scooter.battery)%", label: "battery")
                metric(icon: "point.topleft.down.curvedto.point.bottomright.up", value: scooter.rangeKm.oneDecimal, label: "km range")
                metric(icon: "tag.fill", value: scooter.pricePerMinute.money, label: "per min")
            }

            HStack {
                Text("unlock fee")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text(scooter.unlockFee.money)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }

            Button("Unlock · \(scooter.unlockFee.money)", action: onUnlock)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }

    private func metric(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.lime)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textDim)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceHi))
    }
}
