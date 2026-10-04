import SwiftUI
import MapKit
import CoreLocation

struct MapScreen: View {
    @EnvironmentObject private var store: RideStore

    // Starts framing whatever content exists, then snaps to the rider's own fix
    // the moment one arrives. Never opens on a hardcoded city.
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: Scooter?
    @State private var showUnlock = false
    @State private var didCenter = false

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

            if store.userLocation == nil && !store.locationDenied {
                locatingPill
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    recenterButton
                }
                .padding(.trailing, 16)
                .padding(.bottom, 10)

                if let scooter = selected {
                    ScooterCard(
                        scooter: scooter,
                        distanceMeters: store.userLocation.map { scooter.meters(from: $0) },
                        onUnlock: { showUnlock = true },
                        onClose: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selected = nil }
                        }
                    )
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
        .onAppear(perform: centerOnRiderIfPossible)
        .onChange(of: store.userLocation?.latitude) { _, _ in centerOnRiderIfPossible() }
        .onChange(of: store.active?.id) { _, newValue in
            if newValue != nil {
                showUnlock = false
                selected = nil
            }
        }
    }

    // MARK: - pieces

    private var header: some View {
        VStack(spacing: 8) {
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

            if store.locationDenied {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("location is off — showing a demo area. enable access to see scooters around you.")
                        .font(.system(size: 11.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.amber)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface.opacity(0.95)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.amber.opacity(0.4), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var locatingPill: some View {
        HStack(spacing: 8) {
            ProgressView().tint(Theme.lime).scaleEffect(0.8)
            Text("finding you…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.top, 90)
    }

    private var recenterButton: some View {
        Button {
            didCenter = false
            store.refreshLocation()
            centerOnRiderIfPossible()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.lime)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        }
    }

    // MARK: - camera

    private func centerOnRiderIfPossible() {
        guard !didCenter, let location = store.userLocation else { return }
        didCenter = true
        withAnimation(.easeInOut(duration: 0.5)) {
            camera = .region(MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.013, longitudeDelta: 0.013)
            ))
        }
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
    let distanceMeters: CLLocationDistance?
    let onUnlock: () -> Void
    let onClose: () -> Void

    private var distanceText: String {
        guard let distanceMeters else { return "—" }
        if distanceMeters < 950 {
            return "\(Int(distanceMeters.rounded())) m"
        }
        return String(format: "%.1f km", distanceMeters / 1000)
    }

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
                metric(icon: "figure.walk", value: distanceText, label: "away")
                metric(icon: "battery.75", value: "\(scooter.battery)%", label: "battery")
                metric(icon: "point.topleft.down.curvedto.point.bottomright.up",
                       value: scooter.rangeKm.oneDecimal, label: "km range")
            }

            HStack {
                Text("unlock fee")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text(scooter.unlockFee.money)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("· \(scooter.pricePerMinute.money)/min")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
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
