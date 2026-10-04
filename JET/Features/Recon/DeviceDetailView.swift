import SwiftUI

struct DeviceDetailView: View {
    @ObservedObject var scanner: BLEScanner
    @ObservedObject var device: BLEDevice

    @State private var expanded: String?
    @State private var hexInput: String = "01"

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    header
                    connectionButton

                    if device.services.isEmpty {
                        waiting
                    } else {
                        ForEach(device.services) { service in
                            serviceCard(service)
                        }
                    }

                    deviceLog
                }
                .padding(16)
            }
        }
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .onAppear {
            if device.state != .connected { scanner.connect(device) }
        }
    }

    // MARK: - pieces

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                row("identifier", device.shortIdentifier, mono: true)
                row("state", stateText)
                row("signal", "\(device.rssi) dBm")
                row("connectable", device.isConnectable ? "yes" : "no")
                if !device.advertisedServices.isEmpty {
                    row("advertised", device.advertisedServices.joined(separator: ", "), mono: true)
                }
                if let manufacturer = device.manufacturerHex {
                    row("manufacturer", manufacturer, mono: true)
                }
            }
        }
    }

    private var stateText: String {
        switch device.state {
        case .connected:    return "connected"
        case .connecting:   return "connecting…"
        case .disconnecting:return "disconnecting…"
        default:            return "disconnected"
        }
    }

    private var connectionButton: some View {
        Button {
            device.state == .connected ? scanner.disconnect(device) : scanner.connect(device)
        } label: {
            Text(device.state == .connected ? "Disconnect" : "Connect")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(device.state == .connected ? Theme.text : Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(device.state == .connected ? Theme.surfaceHi : Theme.lime)
                )
        }
    }

    private var waiting: some View {
        Card {
            HStack(spacing: 10) {
                ProgressView().tint(Theme.lime).scaleEffect(0.8)
                Text("enumerating services…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private func serviceCard(_ service: BLEGATTService) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.lime)
                    Text(service.uuid)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    if !service.isPrimary {
                        Text("secondary")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                if service.characteristics.isEmpty {
                    Text("no characteristics")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }

                ForEach(service.characteristics) { characteristic in
                    characteristicRow(characteristic)
                }
            }
        }
    }

    private func characteristicRow(_ characteristic: BLEGATTCharacteristic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded = expanded == characteristic.uuid ? nil : characteristic.uuid
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(characteristic.uuid)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    HStack(spacing: 5) {
                        ForEach(characteristic.properties, id: \.self) { property in
                            Text(property)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(propertyTint(property))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(propertyTint(property).opacity(0.14)))
                        }
                        Spacer()
                    }

                    if let value = characteristic.value {
                        Text(value)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.lime)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)

            if expanded == characteristic.uuid {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        if characteristic.isReadable {
                            actionButton("Read", icon: "arrow.down.circle") {
                                scanner.read(device, characteristic: characteristic.uuid)
                            }
                        }
                        if characteristic.isNotifiable {
                            actionButton(characteristic.isNotifying ? "Stop" : "Notify",
                                         icon: "bell") {
                                scanner.toggleNotify(device, characteristic: characteristic.uuid)
                            }
                        }
                    }

                    if characteristic.isWritable {
                        HStack(spacing: 8) {
                            TextField("", text: $hexInput,
                                      prompt: Text("hex, e.g. 01A4").foregroundStyle(Theme.textDim))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bg))

                            Button {
                                scanner.write(device, characteristic: characteristic.uuid, hex: hexInput)
                            } label: {
                                Text("Write")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.bg)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            Divider().overlay(Theme.stroke)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Theme.lime)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.limeSoft))
        }
    }

    private func propertyTint(_ property: String) -> Color {
        switch property {
        case "read":     return Theme.lime
        case "write", "writeNR": return Theme.amber
        case "notify", "indicate": return Color(hex: 0x4FC3F7)
        default:         return Theme.textDim
        }
    }

    private var deviceLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("device log")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textDim)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(device.log.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.text.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textDim)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: mono ? .monospaced : .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
        }
    }
}
