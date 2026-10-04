import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject private var store: RideStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        balanceCard
                        topUp
                        payment
                        unlockSpec
                        about
                    }
                    .padding(16)
                }
            }
            .navigationTitle("profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.bg, for: .navigationBar)
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("balance")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .textCase(.uppercase)
            Text(store.balance.money)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(Theme.lime)
                .monospacedDigit()
            Text("rider · kanha")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textDim)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private var topUp: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("top up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)

                HStack(spacing: 10) {
                    ForEach([5.0, 10.0, 25.0], id: \.self) { amount in
                        Button {
                            store.topUp(amount)
                        } label: {
                            Text(amount.money)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.surfaceHi))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    private var payment: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text("apple pay")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("auto top-up when balance drops under $5")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.lime)
            }
        }
    }

    private var unlockSpec: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("how unlocking works")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)

                spec("1", "the server signs a token for this ride, valid 60 seconds")
                spec("2", "your phone hands it to the scooter over bluetooth")
                spec("3", "the scooter verifies the signature, then opens the relay")
                spec("4", "a heartbeat every 5s keeps it alive — walk away and it dies")

                Text("the key never lives in this app. a captured token is worthless 60 seconds later, and can't be used twice.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 4)
            }
        }
    }

    private func spec(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Theme.bg)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.lime))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var about: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("JET")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("1.0.0")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }
                Text("scooter sharing client · demo fleet, local token authority")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }
}
