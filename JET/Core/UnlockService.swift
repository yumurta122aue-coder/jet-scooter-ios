import Foundation
import CoreBluetooth

/// The unlocker.
///
/// Flow: scan for the vehicle's BLE service, connect, hand it a server-signed
/// token, wait for the write acknowledgement, then hold the link open with a
/// heartbeat. If the heartbeat stops, the vehicle's dead-man switch drops the
/// relay on its own — the app is not trusted to be the thing that keeps a
/// scooter alive.
final class UnlockService: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case bluetoothOff
        case bluetoothDenied
        case scanning
        case connecting
        case discovering
        case handshaking
        case unlocked
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .scanning, .connecting, .discovering, .handshaking: return true
            default: return false
            }
        }

        var label: String {
            switch self {
            case .idle:            return "ready"
            case .bluetoothOff:    return "bluetooth is off"
            case .bluetoothDenied: return "bluetooth permission denied"
            case .scanning:        return "looking for the scooter"
            case .connecting:      return "connecting"
            case .discovering:     return "reading vehicle services"
            case .handshaking:     return "verifying unlock token"
            case .unlocked:        return "unlocked"
            case .failed(let m):   return m
            }
        }
    }

    // Must match the firmware's GATT table.
    static let serviceUUID   = CBUUID(string: "6A4E0001-9F3B-4C2A-8E11-71D0A5C9B120")
    static let unlockUUID    = CBUUID(string: "6A4E0002-9F3B-4C2A-8E11-71D0A5C9B120")
    static let heartbeatUUID = CBUUID(string: "6A4E0003-9F3B-4C2A-8E11-71D0A5C9B120")
    static let telemetryUUID = CBUUID(string: "6A4E0004-9F3B-4C2A-8E11-71D0A5C9B120")

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var log: [String] = []
    @Published private(set) var vehicleBattery: Int? = nil
    @Published private(set) var signalStrength: Int? = nil

    private var central: CBCentralManager!
    private var vehicle: CBPeripheral?
    private var unlockChar: CBCharacteristic?
    private var heartbeatChar: CBCharacteristic?
    private var telemetryChar: CBCharacteristic?

    private var pendingToken: Data?
    private var targetID: String?
    private var scanTimeout: Timer?
    private var heartbeat: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    // MARK: - public surface

    /// Ask the vehicle to open its relay. `token` is what `Backend.requestUnlock` returned.
    func unlock(scooterID: String, token: Data) {
        pendingToken = token
        targetID = scooterID.uppercased()
        note("token \(token.count)B ready, expires in 60s")

        switch phase {
        case .unlocked:
            writeTokenIfPossible()
        default:
            phase = .scanning
            beginScan()
        }
    }

    /// Leg a rider off. Closing the link is the lock.
    func lock() {
        heartbeat?.invalidate(); heartbeat = nil
        scanTimeout?.invalidate(); scanTimeout = nil

        if let v = vehicle, v.state == .connected {
            if let ch = heartbeatChar {
                v.writeValue(Data([0x00]), for: ch, type: .withoutResponse)
            }
            central.cancelPeripheralConnection(v)
            note("lock command sent")
        }
        vehicle = nil
        unlockChar = nil
        heartbeatChar = nil
        telemetryChar = nil
        pendingToken = nil
        targetID = nil
        vehicleBattery = nil
        phase = .idle
    }

    func reset() {
        heartbeat?.invalidate(); heartbeat = nil
        log.removeAll()
        phase = .idle
    }

    // MARK: - internals

    private func beginScan() {
        guard central.state == .poweredOn else {
            if central.state == .poweredOff { phase = .bluetoothOff }
            if central.state == .unauthorized { phase = .bluetoothDenied }
            return
        }
        note("scanning for \(targetID ?? "any vehicle")")
        central.scanForPeripherals(withServices: [Self.serviceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        scanTimeout?.invalidate()
        scanTimeout = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self, self.phase.isBusy else { return }
            self.central.stopScan()
            self.fail("no scooter responded — walk closer and try again")
        }
    }

    private func writeTokenIfPossible() {
        guard let v = vehicle, let ch = unlockChar, let token = pendingToken else { return }
        phase = .handshaking
        v.writeValue(token, for: ch, type: .withResponse)
        note("token written, waiting for vehicle")
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, let v = self.vehicle, let ch = self.heartbeatChar else { return }
            guard v.state == .connected else { return }
            v.writeValue(Data([0x01]), for: ch, type: .withoutResponse)
        }
        note("heartbeat armed — 5s interval")
    }

    private func note(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.append("\(stamp)  \(text)")
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        note(message)
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}

// MARK: - CBCentralManagerDelegate

extension UnlockService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            note("bluetooth ready")
            if phase.isBusy { beginScan() }
        case .poweredOff:
            phase = .bluetoothOff
        case .unauthorized:
            phase = .bluetoothDenied
        case .unsupported:
            fail("this device has no bluetooth LE")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advertised = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""

        // Prefer the exact vehicle, but accept a name match if the fleet rotates ids.
        if let target = targetID, !advertised.isEmpty, !advertised.uppercased().contains(target) {
            note("skipping \(advertised)")
            return
        }

        central.stopScan()
        scanTimeout?.invalidate()

        vehicle = peripheral
        peripheral.delegate = self
        signalStrength = RSSI.intValue
        note("found \(advertised.isEmpty ? peripheral.identifier.uuidString : advertised) @ \(RSSI) dBm")

        phase = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        note("connected")
        phase = .discovering
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        fail("connection failed: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        heartbeat?.invalidate(); heartbeat = nil
        if phase == .unlocked {
            note("link dropped — vehicle armed its dead-man switch")
        }
        if case .failed = phase {
            // keep the failure on screen; the rider needs to read it
        } else if phase != .idle {
            phase = .idle
        }
    }
}

// MARK: - CBPeripheralDelegate

extension UnlockService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            fail("service discovery failed")
            return
        }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics(
                [Self.unlockUUID, Self.heartbeatUUID, Self.telemetryUUID],
                for: service
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil, let chars = service.characteristics else {
            fail("characteristic discovery failed")
            return
        }
        for ch in chars {
            switch ch.uuid {
            case Self.unlockUUID:    unlockChar = ch
            case Self.heartbeatUUID: heartbeatChar = ch
            case Self.telemetryUUID: telemetryChar = ch
            default: break
            }
        }

        guard unlockChar != nil else {
            fail("this scooter isn't exposing an unlock channel")
            return
        }

        note("gatt ready (\(chars.count) characteristics)")
        writeTokenIfPossible()
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            fail("write rejected: \(error.localizedDescription)")
            return
        }

        if characteristic.uuid == Self.unlockUUID {
            note("vehicle accepted the token")
            phase = .unlocked
            startHeartbeat()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }

        if characteristic.uuid == Self.unlockUUID {
            let reply = String(data: data, encoding: .utf8) ?? hex(data)
            note("vehicle says: \(reply)")
            if reply.uppercased().contains("DENY") {
                fail("vehicle refused the token")
            }
            return
        }

        if characteristic.uuid == Self.telemetryUUID, let first = data.first {
            vehicleBattery = Int(first)
            note("vehicle battery \(first)%")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            note("notify setup failed: \(error.localizedDescription)")
        }
    }
}
