import SwiftUI

/// The multi-tool hub: radio reconnaissance and card inspection, plus the ride
/// client's own diagnostics.
enum ToolRoute: Hashable {
    case ble
    case nfc
}

struct ToolsScreen: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        toolCard(
                            route: .ble,
                            icon: "antenna.radiowaves.left.and.right",
                            title: "BLE recon",
                            subtitle: "Unfiltered scan. Find a device even when it advertises no name, connect, enumerate its GATT table, read and write."
                        )
                        toolCard(
                            route: .nfc,
                            icon: "wave.3.right",
                            title: "NFC card",
                            subtitle: "Read contactless cards, identify the technology, pull the UID, send raw MIFARE commands."
                        )

                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("why these two live together")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.text)
                                Text("A shared vehicle is two radios and a lock. The unlock conversation happens over BLE; the vehicle's identity and payment live on a card or a tag. Having both instruments in one place means you can watch the whole thing without guessing.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .navigationDestination(for: ToolRoute.self) { route in
                switch route {
                case .ble: ReconScreen()
                case .nfc: NFCCardScreen()
                }
            }
        }
    }

    private func toolCard(route: ToolRoute, icon: String, title: String, subtitle: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.limeSoft)
                        .frame(width: 50, height: 50)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.lime)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
