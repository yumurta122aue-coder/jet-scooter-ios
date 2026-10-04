import SwiftUI

struct ReconScreen: View {
    @StateObject private var scanner = BLEScanner()
    @State private var showLog = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    controlBar

                    if scanner.devices.isEmpty {
                        emptyState
                    } else {
                        deviceList
                    }

                    if showLog {
                        logPanel
                    }
                }
            }
            .navigationTitle("ble recon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { showLog.toggle() }
                    } label: {
                        Image(systemName: showLog ? "chevron.down.circle" : "chevron.up.circle")
                            .foregroundStyle(Theme.textDim)
                    }
                }
            }
            .navigationDestination(for: BLEDevice.self) { device in
                DeviceDetailView(scanner: scanner, device: device)
            }
            .onDisappear { scanner.stopScan() }
        }
    }

    // MARK: - pieces

    private var controlBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    scanner.toggleScan()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: scanner.isScanning ? "stop.fill" : "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .bold))
                        Text(scanner.isScanning ? "Stop" : "Scan everything")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.lime))
                }

                if scanner.isScanning {
                    ProgressView().tint(Theme.lime).frame(width: 28)
                }
            }

            HStack(spacing: 14) {
                label("\(scanner.devices.count)", "found")
                label("\(scanner.unnamedCount)", "unnamed")
                label(scanner.stateText, "radio")
                Spacer()
            }
        }
        .padding(16)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private func label(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .textCase(.uppercase)
        }
    }

    private var deviceList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(scanner.devices) { device in
                    NavigationLink(value: device) {
                        DeviceRow(device: device)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textDim)
            Text(scanner.isScanning ? "listening…" : "no scan running")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("unfiltered scan — unnamed advertisers included")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(scanner.eventLog.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.text.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: scanner.eventLog.count) { _, count in
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
        .frame(height: 150)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }
}

struct DeviceRow: View {
    @ObservedObject var device: BLEDevice

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(device.isUnnamed ? Theme.amber.opacity(0.16) : Theme.limeSoft)
                    .frame(width: 42, height: 42)
                Image(systemName: device.isUnnamed ? "questionmark" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(device.isUnnamed ? Theme.amber : Theme.lime)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(device.shortIdentifier)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    if !device.advertisedServices.isEmpty {
                        Text("· \(device.advertisedServices.count) svc")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.textDim)
                    }
                    if device.state == .connected {
                        Text("· connected")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Theme.lime)
                    }
                    if !device.isConnectable {
                        Text("· not connectable")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Theme.danger)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                signalBars
                Text("\(device.rssi) dBm")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private var signalBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < device.signalBars ? Theme.lime : Theme.stroke)
                    .frame(width: 3.5, height: 5 + CGFloat(index) * 4)
            }
        }
    }
}
