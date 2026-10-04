import Foundation
import CoreLocation

struct Scooter: Identifiable, Hashable {
    let id: String
    let latitude: Double
    let longitude: Double
    let battery: Int
    let rangeKm: Double
    let pricePerMinute: Double
    let unlockFee: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var batteryTint: String {
        if battery > 55 { return "high" }
        if battery > 20 { return "mid" }
        return "low"
    }

    /// Straight-line metres to a point. Used for "how far do I have to walk".
    func meters(from origin: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
    }
}

struct Ride: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let scooterID: String
    let startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double = 0
    var cost: Double = 0

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var isActive: Bool { endedAt == nil }
}

/// Route point for the polyline drawn on the ride summary.
struct TrackPoint: Identifiable, Hashable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
}

extension Scooter {

    /// Stable-looking vehicle ids, matching the format the firmware advertises.
    static let idPool = [
        "SK-8F31A2", "SK-2B77C4", "SK-9D04E1", "SK-5A19F8",
        "SK-C30B66", "SK-1E8A05", "SK-77C2D9", "SK-4F6B12",
        "SK-A18D3E"
    ]

    /// Scatters a fleet on a rough ring around the rider, 145 m to ~780 m out.
    ///
    /// This is the piece that makes the app correct wherever it is opened: the
    /// fleet is generated from the device's own fix, not from a baked-in grid.
    /// Longitude is divided by cos(latitude) so the ring stays circular instead
    /// of squashing as you move away from the equator.
    static func fleet(around center: CLLocationCoordinate2D, count: Int = 7) -> [Scooter] {
        let pool = idPool.shuffled()
        let usable = min(count, pool.count)
        let lonScale = 1.0 / max(cos(center.latitude * .pi / 180.0), 0.25)

        return (0..<usable).map { index in
            let angle = (Double(index) / Double(usable)) * 2 * .pi + Double.random(in: -0.45...0.45)
            let radius = Double.random(in: 0.0013...0.0070)   // degrees ≈ 145 m … 780 m

            let battery = Int.random(in: 14...98)

            return Scooter(
                id: pool[index],
                latitude: center.latitude + radius * cos(angle),
                longitude: center.longitude + radius * sin(angle) * lonScale,
                battery: battery,
                rangeKm: (Double(battery) * 0.44).rounded(toPlaces: 1),
                pricePerMinute: Bool.random() ? 0.29 : 0.33,
                unlockFee: 1.00
            )
        }
    }

    /// Only used when location access is refused and there is nothing real to
    /// draw. A neutral mid-Atlantic grid, so it is obvious it is not a real city.
    static let fallbackFleet: [Scooter] = fleet(
        around: CLLocationCoordinate2D(latitude: 40.7135, longitude: -74.0040)
    )
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
