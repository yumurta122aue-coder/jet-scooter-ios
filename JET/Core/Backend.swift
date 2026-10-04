import Foundation
import CryptoKit

/// A short-lived, single-use unlock grant.
///
/// Layout the vehicle expects on the wire (36 bytes):
///   ride_id(8) || expires_seconds_be(4) || nonce(8) || hmac_sha256(...)[0..<16]
struct UnlockToken {
    let rideID: String
    let payload: Data
    let expiresAt: Date
}

enum BackendError: LocalizedError {
    case vehicleUnavailable
    case serverUnreachable

    var errorDescription: String? {
        switch self {
        case .vehicleUnavailable: return "that scooter just got taken"
        case .serverUnreachable:  return "can't reach the server"
        }
    }
}

/// Stand-in for the real service.
///
/// The important architectural point: the app never holds the fleet key on a
/// production deployment. It asks the server for a signed, expiring token and
/// the vehicle verifies that token offline. Here the key is local so the demo
/// works with no infrastructure, and the byte layout matches the ESP32
/// firmware exactly — drop in a real URL and nothing else changes.
final class Backend {
    static let shared = Backend()

    /// Demo-only fleet key. Rotate per fleet, never ship a static one.
    private let fleetKey = SymmetricKey(data: SHA256.hash(data: Data("jet-demo-fleet-key-v1".utf8)))

    private init() {}

    func requestUnlock(scooterID: String) async throws -> UnlockToken {
        try await Task.sleep(for: .milliseconds(450))

        let rideBytes = Self.randomBytes(8)
        let nonce     = Self.randomBytes(8)
        let expires   = UInt32(Date().timeIntervalSince1970) + 60

        var bigEndian = expires.bigEndian
        let expiresBytes = withUnsafeBytes(of: &bigEndian) { Array($0) }

        var blob = rideBytes
        blob.append(contentsOf: expiresBytes)
        blob.append(contentsOf: nonce)

        let mac = HMAC<SHA256>.authenticationCode(for: blob, using: fleetKey)
        let signature = Data(mac).prefix(16)

        return UnlockToken(
            rideID: rideBytes.map { String(format: "%02X", $0) }.joined(),
            payload: blob + signature,
            expiresAt: Date().addingTimeInterval(60)
        )
    }

    func endRide(_ ride: Ride) async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    func report(_ text: String) {
        // Seam for real telemetry later.
    }

    private static func randomBytes(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }
}
