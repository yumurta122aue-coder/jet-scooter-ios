import Foundation
import CoreBluetooth

/// Unfiltered BLE recon.
///
/// The scooter-sharing app's own binary is not where the unlock lives — the
/// protocol lives in the scooter. A vehicle in range will happily describe its
/// own GATT table to anyone who asks, which is why this scanner exists: stand
/// next to the thing, find it even when it advertises no name, connect, and read
/// the services and characteristics straight off it.
///
/// iOS constraints worth knowing before reading the output:
///   - Classic Bluetooth (BR/EDR) is invisible. BLE only.
///   - There is no MAC address. CoreBluetooth hands out a per-phone UUID.
///   - A device that is not advertising cannot be found or connected to.
///   - A peripheral already held by another app will refuse the connection.
final class BLEScanner: NSObject, ObservableObject {

    @Published private(set) var devices: [BLEDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var eventLog: [String] = []
    @Published var selected: BLEDevice?

    private var central: CBCentralManager!
    private var index: [UUID: BLEDevice] = [:]
    private var resortTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    var stateText: String {
        switch state {
        case .poweredOn:     return "radio on"
        case .poweredOff:    return "bluetooth is off"
        case .unauthorized:  return "bluetooth permission denied"
        case .unsupported:   return "no BLE on this device"
        case .resetting:     return "radio resetting"
        default:             return "initialising"
        }
    }

    var unnamedCount: Int { devices.filter(\.isUnnamed).count }

    // MARK: - scanning

    func startScan() {
        guard state == .poweredOn else {
            note("cannot scan: \(stateText)")
            return
        }
        devices.removeAll()
        index.removeAll()
        eventLog.removeAll()

        // nil services = ask for everything. This is the whole point: a device
        // that advertises no name and no service UUID still shows up here.
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        isScanning = true
        note("scanning unfiltered — every advertiser in range")

        resortTimer?.invalidate()
        resortTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, self.isScanning else { return }
            self.devices = self.devices.sorted { $0.rssi > $1.rssi }
        }
    }

    func stopScan() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
        resortTimer?.invalidate()
        resortTimer = nil
        note("scan stopped — \(devices.count) devices seen")
    }

    func toggleScan() { isScanning ? stopScan() : startScan() }

    // MARK: - connection

    func connect(_ device: BLEDevice) {
        central.stopScan()
        isScanning = false
        resortTimer?.invalidate()
        note("connecting to \(device.displayName)")
        central.connect(device.peripheral, options: nil)
    }

    func disconnect(_ device: BLEDevice) {
        central.cancelPeripheralConnection(device.peripheral)
    }

    // MARK: - interaction

    func read(_ device: BLEDevice, characteristic uuid: String) {
        guard let match = find(device, uuid) else { return }
        device.peripheral.readValue(for: match)
        device.note("read \(uuid)")
    }

    func toggleNotify(_ device: BLEDevice, characteristic uuid: String) {
        guard let match = find(device, uuid) else { return }
        let turningOn = !match.isNotifying
        device.peripheral.setNotifyValue(turningOn, for: match)
        device.note("\(turningOn ? "subscribe" : "unsubscribe") \(uuid)")
    }

    func write(_ device: BLEDevice, characteristic uuid: String, hex: String) {
        guard let match = find(device, uuid) else { return }
        guard let data = Self.data(fromHex: hex) else {
            device.note("write rejected: '\(hex)' is not hex")
            return
        }
        let type: CBCharacteristicWriteType =
            match.properties.contains("write") ? .withResponse : .withoutResponse
        device.peripheral.writeValue(data, for: match, type: type)
        device.note("write \(data.count)B → \(uuid): \(hex.uppercased())")
    }

    private func find(_ device: BLEDevice, _ uuid: String) -> CBCharacteristic? {
        guard let service = device.peripheral.services?
            .first(where: { service in
                service.characteristics?.contains { $0.uuid.uuidString == uuid } ?? false
            }),
            let characteristic = service.characteristics?
                .first(where: { $0.uuid.uuidString == uuid })
        else { return nil }
        return characteristic
    }

    // MARK: - helpers

    private func note(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        eventLog.append("\(stamp)  \(text)")
        if eventLog.count > 200 { eventLog.removeFirst(eventLog.count - 200) }
    }

    private func device(for peripheral: CBPeripheral) -> BLEDevice? {
        index[peripheral.identifier]
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func data(fromHex hex: String) -> Data? {
        let cleaned = hex.filter { $0.isHexDigit }
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var bytes = [UInt8]()
        var iterator = cleaned.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            guard let byte = UInt8(String([high, low]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return Data(bytes)
    }

    private func characteristicPropertyNames(_ properties: CBCharacteristicProperties) -> [String] {
        var names: [String] = []
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.writeWithoutResponse) { names.append("writeNR") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        if properties.contains(.broadcast) { names.append("broadcast") }
        if properties.contains(.authenticatedSignedWrites) { names.append("signedWrite") }
        if properties.contains(.extendedProperties) { names.append("extended") }
        return names.isEmpty ? ["—"] : names
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEScanner: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        note(stateText)
        if central.state != .poweredOn, isScanning {
            isScanning = false
            resortTimer?.invalidate()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map(\.uuidString) ?? []
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)
            .map(BLEScanner.hex)

        if let existing = index[peripheral.identifier] {
            existing.rssi = RSSI.intValue
            existing.lastSeen = Date()
            if let name, !name.isEmpty { existing.advertisedName = name }
            return
        }

        let device = BLEDevice(peripheral: peripheral,
                               rssi: RSSI.intValue,
                               advertisedName: name,
                               isConnectable: connectable,
                               advertisedServices: services,
                               manufacturerHex: manufacturer)
        peripheral.delegate = self
        index[peripheral.identifier] = device
        devices.append(device)
        note("found \(device.displayName)  \(RSSI) dBm  connectable=\(connectable)")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let device = device(for: peripheral) else { return }
        device.state = .connected
        device.note("connected — enumerating GATT")
        note("connected to \(device.displayName)")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard let device = device(for: peripheral) else { return }
        device.state = .disconnected
        device.note("connect failed: \(error?.localizedDescription ?? "refused")")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        guard let device = device(for: peripheral) else { return }
        device.state = .disconnected
        device.note("disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
    }
}

// MARK: - CBPeripheralDelegate

extension BLEScanner: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let device = device(for: peripheral) else { return }
        if let error {
            device.note("service discovery failed: \(error.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        device.note("\(services.count) services")
        device.services = services.map {
            BLEGATTService(uuid: $0.uuid.uuidString, isPrimary: $0.isPrimary, characteristics: [])
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let device = device(for: peripheral) else { return }
        if let error {
            device.note("characteristics failed for \(service.uuid): \(error.localizedDescription)")
            return
        }

        let mapped = (service.characteristics ?? []).map { characteristic in
            BLEGATTCharacteristic(uuid: characteristic.uuid.uuidString,
                                  properties: characteristicPropertyNames(characteristic.properties))
        }

        if let idx = device.services.firstIndex(where: { $0.uuid == service.uuid.uuidString }) {
            device.services[idx].characteristics = mapped
        }
        device.note("\(service.uuid.uuidString) → \(mapped.count) characteristics")

        // Read anything readable without being asked; it is the fastest way to
        // see what a device is willing to tell you.
        for characteristic in service.characteristics ?? [] where characteristic.properties.contains(.read) {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let device = device(for: peripheral) else { return }
        guard error == nil, let data = characteristic.value else { return }

        let uuid = characteristic.uuid.uuidString
        let hex = BLEScanner.hex(data)

        for serviceIndex in device.services.indices {
            if let charIndex = device.services[serviceIndex].characteristics
                .firstIndex(where: { $0.uuid == uuid }) {
                device.services[serviceIndex].characteristics[charIndex].value = hex
            }
        }

        let asText = String(data: data, encoding: .utf8)
        device.note("← \(uuid): \(hex)\(asText.map { "  \"\($0)\"" } ?? "")")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let device = device(for: peripheral) else { return }
        if let error {
            device.note("write failed: \(error.localizedDescription)")
        } else {
            device.note("✓ write accepted by \(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let device = device(for: peripheral) else { return }
        let uuid = characteristic.uuid.uuidString
        for serviceIndex in device.services.indices {
            if let charIndex = device.services[serviceIndex].characteristics
                .firstIndex(where: { $0.uuid == uuid }) {
                device.services[serviceIndex].characteristics[charIndex].isNotifying = characteristic.isNotifying
            }
        }
        if let error {
            device.note("notify failed: \(error.localizedDescription)")
        } else {
            device.note(characteristic.isNotifying ? "notifying on \(uuid)" : "notify off \(uuid)")
        }
    }
}
