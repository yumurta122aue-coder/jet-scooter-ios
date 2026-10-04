import SwiftUI

/// What the rider sees while the handshake runs. The log is real: every line is
/// emitted by UnlockService as the BLE conversation progresses.
struct UnlockSheet: View {
    @EnvironmentObject private var store: RideStore
    @Environment(\.dismiss) private var dismiss
    let scooter: Scooter

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            handle

            HStack(spacing: 14) {
                phaseRing
                VStack(alignment: .leading, spacing: 3) {
                    Text(scooter.id)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(store.unlock.phase.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tint)
                }
                Spacer()
            }

            Divider().overlay(Theme.stroke)

            Text("handshake")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textDim)
                .textCase(.uppercase)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if store.unlock.log.isEmpty {
                        Text("waiting for radio…")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                    ForEach(Array(store.unlock.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.text.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 180)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bg))

            if case .failed = store.unlock.phase {
                Button("Try again") {
                    store.unlockScooter(scooter)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Cancel") {
                    store.unlock.lock()
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surfaceHi))
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Theme.surface)
        .onAppear {
            if store.unlock.phase == .idle || !store.unlock.phase.isBusy {
                store.unlockScooter(scooter)
            }
        }
        .onChange(of: store.unlock.phase) { _, phase in
            if phase == .unlocked {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
            }
        }
    }

    private var tint: Color {
        switch store.unlock.phase {
        case .unlocked: return Theme.lime
        case .failed:   return Theme.danger
        default:        return Theme.textDim
        }
    }

    private var handle: some View {
        HStack {
            Text("unlocking")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Spacer()
        }
    }

    private var phaseRing: some View {
        ZStack {
            Circle()
                .stroke(Theme.stroke, lineWidth: 4)
                .frame(width: 52, height: 52)

            switch store.unlock.phase {
            case .unlocked:
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Theme.lime)
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Theme.danger)
            case .idle, .bluetoothOff, .bluetoothDenied:
                Image(systemName: "bolt.slash")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            default:
                ProgressView()
                    .tint(Theme.lime)
            }
        }
    }
}
