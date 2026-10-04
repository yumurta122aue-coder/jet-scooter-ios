import Foundation
import CoreBluetooth

/// A peripheral as seen by a scan, plus whatever we learn about it by connecting.
///
/// Deliberately unfiltered: this scanner asks CoreBluetooth for every device in
/// range, including ones that advertise no name at all. On iOS you never get a
/// MAC address — the system hands you a per-device UUID that is stable on this
/// phone and meaningless anywhere else.
final class BLEDevice: ObservableObject, Identifiable {
    let id: UUID
    let peripheral: CBPeripheral

    @Published var advertisedName: String?
    @Published var rssi: Int
    @Published var isConnectable: Bool
    @Published var advertisedServices: [String]
    @Published var manufacturerHex: String?
    @Published var lastSeen: Date
    @Published var state: CBPeripheralState = .disconnected
    @Published var services: [BLEGATTService] = []
    @Published var log: [String] = []

    init(peripheral: CBPeripheral, rssi: Int, advertisedName: String?,
         isConnectable: Bool, advertisedServices: [String], manufacturerHex: String?) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.rssi = rssi
        self.advertisedName = advertisedName
        self.isConnectable = isConnectable
        self.advertisedServices = advertisedServices
        self.manufacturerHex = manufacturerHex
        self.lastSeen = Date()
    }

    /// What to show in a list. An unnamed peripheral is the interesting case.
    var displayName: String {
        if let advertisedName, !advertisedName.isEmpty { return advertisedName }
        return "unnamed · \(id.uuidString.prefix(8))"
    }

    var isUnnamed: Bool {
        advertisedName?.isEmpty ?? true
    }

    var shortIdentifier: String {
        String(id.uuidString.prefix(8))
    }

    var signalBars: Int {
        // -40 dBm or better is 4 bars, -100 or worse is 0.
        let clamped = min(max(rssi, -100), -40)
        return Int(round(Double(clamped + 100) / 15.0))
    }

    func note(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.append("\(stamp)  \(text)")
    }
}

struct BLEGATTService: Identifiable {
    let id = UUID()
    let uuid: String
    let isPrimary: Bool
    var characteristics: [BLEGATTCharacteristic]
}

extension BLEDevice: Hashable {
    static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct BLEGATTCharacteristic: Identifiable {
    let id = UUID()
    let uuid: String
    let properties: [String]
    var value: String?
    var isNotifying: Bool = false

    var isReadable: Bool { properties.contains("read") }
    var isWritable: Bool { properties.contains("write") || properties.contains("writeNR") }
    var isNotifiable: Bool { properties.contains("notify") || properties.contains("indicate") }
}
