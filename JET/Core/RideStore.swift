import Foundation
import CoreLocation
import Combine

/// Single source of truth for the rider's session: fleet, active ride, meter,
/// balance and history. The unlocker is owned here so the ride starts exactly
/// when the hardware says it started, not when the UI hopes it did.
final class RideStore: NSObject, ObservableObject {

    /// Only reached when location is refused — before that, everything is built
    /// from the device's own fix.
    static let fallbackCenter = CLLocationCoordinate2D(latitude: 40.7135, longitude: -74.0040)

    @Published var scooters: [Scooter] = []
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var locationDenied = false
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
    private var fleetBuilt = false
    private var pendingScooter: Scooter?

    override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 3

        // The ride begins on hardware truth, not on a tap.
        unlock.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                if phase == .unlocked, self.active == nil, let scooter = self.pendingScooter {
                    self.beginRide(on: scooter)
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

        requestLocationIfPossible()
    }

    // MARK: - location

    private func requestLocationIfPossible() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            useFallbackFleet()
        @unknown default:
            break
        }
    }

    /// Refused location: there is nothing real to draw, so say so plainly rather
    /// than pretending the rider is somewhere they are not.
    private func useFallbackFleet() {
        locationDenied = true
        if scooters.isEmpty { scooters = Scooter.fallbackFleet }
    }

    /// Called by the map's recenter button.
    func refreshLocation() {
        guard !locationDenied else { return }
        locationManager.requestLocation()
    }

    func scooter(withID id: String) -> Scooter? {
        if let match = scooters.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            return match
        }
        return Scooter.fallbackFleet.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    // MARK: - live numbers

    var elapsed: TimeInterval { active?.duration ?? 0 }

    var liveCost: Double {
        guard let scooter = liveScooter, active != nil else { return 0 }
        let minutes = elapsed / 60.0
        return scooter.unlockFee + scooter.pricePerMinute * minutes
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

        active = nil
        pendingScooter = nil
        stopTicker()
        locationManager.stopUpdatingLocation()
        unlock.lock()

        // Let the ride cover finish dismissing before the receipt cover presents.
        let finished = ride
        DispatchQueue.main.async { [weak self] in
            self?.receipt = finished
        }

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
        guard let fix = locations.last else { return }

        if userLocation == nil {
            userLocation = fix.coordinate
        }

        // First usable fix decides where the fleet lives.
        if !fleetBuilt, fix.horizontalAccuracy > 0, fix.horizontalAccuracy < 500 {
            fleetBuilt = true
            locationDenied = false
            scooters = Scooter.fleet(around: fix.coordinate)
        }

        // Everything below is metering, which only matters mid-ride.
        guard active != nil else { return }

        defer { lastFix = fix }
        if let previous = lastFix {
            let delta = fix.distance(from: previous)
            // Ignore GPS jitter and impossible jumps.
            if delta > 0.5 && delta < 80 {
                distanceMeters += delta
            }
        }
        track.append(TrackPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationDenied = false
            manager.requestLocation()
        case .denied, .restricted:
            useFallbackFleet()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix degrades to time-only pricing. Never block a ride on GPS.
        if let clError = error as? CLError, clError.code == .denied {
            useFallbackFleet()
        }
    }
}
