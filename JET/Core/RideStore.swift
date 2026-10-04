import Foundation
import CoreLocation
import Combine

/// Single source of truth for the rider's session: fleet, active ride, meter,
/// balance and history. The unlocker is owned here so the ride starts exactly
/// when the hardware says it started, not when the UI hopes it did.
final class RideStore: NSObject, ObservableObject {

    static let demoCenter = CLLocationCoordinate2D(latitude: 40.7135, longitude: -74.0040)

    @Published var scooters: [Scooter] = Scooter.demoFleet
    @Published var active: Ride?
    @Published var liveScooter: Scooter?
    @Published var history: [Ride] = []
    @Published var receipt: Ride?
    @Published var balance: Double = 24.50
    @Published var distanceMeters: Double = 0
    @Published var track: [TrackPoint] = []
    @Published var now: Date = Date()
    @Published var alert: String?

    let unlock = UnlockService()
    private let backend = Backend.shared
    private var ticker: Timer?
    private var bag = Set<AnyCancellable>()
    private let locationManager = CLLocationManager()
    private var lastFix: CLLocation?

    override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
        locationManager.requestWhenInUseAuthorization()

        // The ride begins on hardware truth, not on a tap.
        unlock.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                if phase == .unlocked, self.active == nil, let s = self.pendingScooter {
                    self.beginRide(on: s)
                }
                if case .failed(let message) = phase {
                    self.alert = message
                }
            }
            .store(in: &bag)

        history = [
            Ride(scooterID: "SK-5A19F8",
                 startedAt: Date().addingTimeInterval(-86400 * 1),
                 endedAt: Date().addingTimeInterval(-86400 * 1 + 742),
                 distanceMeters: 1840, cost: 4.59),
            Ride(scooterID: "SK-9D04E1",
                 startedAt: Date().addingTimeInterval(-86400 * 3),
                 endedAt: Date().addingTimeInterval(-86400 * 3 + 415),
                 distanceMeters: 960, cost: 3.28)
        ]
    }

    private var pendingScooter: Scooter?

    // MARK: - live numbers

    var elapsed: TimeInterval { active?.duration ?? 0 }

    var liveCost: Double {
        guard let s = liveScooter, active != nil else { return 0 }
        let minutes = elapsed / 60.0
        return s.unlockFee + s.pricePerMinute * minutes
    }

    var distanceKm: Double { distanceMeters / 1000.0 }

    // MARK: - flow

    func unlockScooter(_ scooter: Scooter) {
        pendingScooter = scooter
        alert = nil
        unlock.reset()

        Task {
            do {
                let token = try await backend.requestUnlock(scooterID: scooter.id)
                await MainActor.run {
                    self.unlock.unlock(scooterID: scooter.id, token: token.payload)
                }
            } catch {
                await MainActor.run {
                    self.alert = error.localizedDescription
                }
            }
        }
    }

    private func beginRide(on scooter: Scooter) {
        let ride = Ride(scooterID: scooter.id, startedAt: Date())
        liveScooter = scooter
        active = ride
        distanceMeters = 0
        track = [TrackPoint(latitude: scooter.latitude, longitude: scooter.longitude)]
        lastFix = nil
        startTicker()
        locationManager.startUpdatingLocation()
    }

    func endRide() {
        guard var ride = active else { return }
        ride.endedAt = Date()
        ride.distanceMeters = distanceMeters
        ride.cost = liveCost

        balance = max(0, balance - ride.cost)
        history.insert(ride, at: 0)
        receipt = ride

        active = nil
        pendingScooter = nil
        stopTicker()
        locationManager.stopUpdatingLocation()
        unlock.lock()

        Task { try? await backend.endRide(ride) }
    }

    func clearReceipt() { receipt = nil }

    func dismissAlert() { alert = nil }

    func topUp(_ amount: Double) { balance += amount }

    // MARK: - ticker

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

extension RideStore: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, active != nil else { return }
        defer { lastFix = fix }

        if let previous = lastFix {
            let delta = fix.distance(from: previous)
            // Ignore GPS noise and impossible jumps.
            if delta > 0.5 && delta < 80 {
                distanceMeters += delta
            }
        }
        track.append(TrackPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // No prompt spam: the map still works, only distance metering degrades.
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Metering degrades to time-only pricing; never block a ride on GPS.
    }
}
