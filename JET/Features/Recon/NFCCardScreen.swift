import SwiftUI

struct NFCCardScreen: View {
    @StateObject private var tool = NFCCardTool()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if !tool.readingAvailable {
                        unavailableCard
                    } else {
                        entitlementNote
                    }

                    readButton

                    if let summary = tool.summary {
                        summaryCard(summary)
                    }

                    rawCommandCard
                    logCard
                }
                .padding(16)
            }
        }
        .navigationTitle("nfc card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
    }

    // MARK: - pieces

    private var unavailableCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.amber)
                    Text("no nfc reader on this device")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                Text("Core NFC reports tag reading is unavailable. On iPhone this usually means the hardware generation or a region restriction.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var entitlementNote: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Theme.lime)
                    Text("what iOS allows here")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                bullet("Reads ISO 14443, ISO 15693 and FeliCa, and can send raw commands to them.")
                bullet("Cannot read MIFARE Classic beyond the UID — Apple excludes that family from Core NFC.")
                bullet("Cannot emulate a card. iOS has no host card emulation, and the Secure Element is Apple Pay only.")
                bullet("Needs the NFC Tag Reading entitlement, which a free Apple ID cannot sign.")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.lime).frame(width: 4, height: 4).padding(.top, 6)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readButton: some View {
        Button {
            tool.isReading ? tool.stop() : tool.start()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tool.isReading ? "stop.fill" : "wave.3.right")
                    .font(.system(size: 14, weight: .bold))
                Text(tool.isReading ? "Stop" : "Read a card")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.lime))
        }
    }

    private func summaryCard(_ summary: NFCCardTool.CardSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                Text("last card")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .textCase(.uppercase)
                row("technology", summary.technology)
                row("identifier", summary.identifier, mono: true)
                row("detail", summary.detail)
                if let ndef = summary.ndef {
                    row("ndef", ndef)
                }
            }
        }
    }

    private var rawCommandCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("raw mifare command")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    TextField("", text: $tool.rawCommand,
                              prompt: Text("60").foregroundStyle(Theme.textDim))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.bg))

                    Button {
                        tool.sendRawMifare()
                    } label: {
                        Text("Send")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.lime))
                    }
                }

                Text("60 = GET_VERSION · 30 04 = READ block 4 · 3A 04 05 06 = WRITE block 4")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private var logCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("card log")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .textCase(.uppercase)

                if tool.lines.isEmpty {
                    Text("nothing yet")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }

                ForEach(Array(tool.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.text.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textDim)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: design(mono)))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func design(_ mono: Bool) -> Font.Design { mono ? .monospaced : .rounded }
}
