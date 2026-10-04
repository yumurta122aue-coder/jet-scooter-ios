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

/// Route point for the mini map drawn on the ride summary.
struct TrackPoint: Identifiable, Hashable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
}

extension Scooter {
    /// Demo fleet. Coordinates are a generic downtown grid so the app has
    /// something to draw before a real `/vehicles` endpoint is wired in.
    static let demoFleet: [Scooter] = [
        Scooter(id: "SK-8F31A2", latitude: 40.71380, longitude: -74.00560, battery: 92, rangeKm: 41.0, pricePerMinute: 0.29, unlockFee: 1.00),
        Scooter(id: "SK-2B77C4", latitude: 40.71120, longitude: -74.00890, battery: 68, rangeKm: 30.5, pricePerMinute: 0.29, unlockFee: 1.00),
        Scooter(id: "SK-9D04E1", latitude: 40.71560, longitude: -74.00210, battery: 41, rangeKm: 18.2, pricePerMinute: 0.33, unlockFee: 1.00),
        Scooter(id: "SK-5A19F8", latitude: 40.70990, longitude: -74.00330, battery: 17, rangeKm: 7.4,  pricePerMinute: 0.33, unlockFee: 1.00),
        Scooter(id: "SK-C30B66", latitude: 40.71710, longitude: -74.00980, battery: 84, rangeKm: 37.9, pricePerMinute: 0.29, unlockFee: 1.00),
        Scooter(id: "SK-1E8A05", latitude: 40.71050, longitude: -73.99940, battery: 55, rangeKm: 24.6, pricePerMinute: 0.29, unlockFee: 1.00),
        Scooter(id: "SK-77C2D9", latitude: 40.71490, longitude: -73.99780, battery: 78, rangeKm: 34.8, pricePerMinute: 0.29, unlockFee: 1.00)
    ]

    static func find(_ id: String) -> Scooter? {
        demoFleet.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }
}
