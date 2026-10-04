import SwiftUI

/// In-app API console.
///
/// The point of this screen: the one thing standing between a working client and
/// a demo is a bearer token, and that token can only be minted by an SMS sent to
/// the rider's own phone. So rather than hardcode guesses at route names, this
/// lets the token and the exact path be dropped in and used immediately — no
/// rebuild, no code change.
///
/// Paste a token, type the path you saw in the proxy, send. If it answers 200,
/// that call is real, and it can be saved as a preset and fired again.
struct APIConsoleScreen: View {
    private let client = APIClient()

    @AppStorage("jet.api.base")  private var base: String = "https://api.gojet.app"
    @AppStorage("jet.api.path")  private var path: String = "/api/v1/auth/token/refresh"
    @AppStorage("jet.api.token") private var token: String = ""
    @AppStorage("jet.api.body")  private var requestBody: String = "{}"

    @State private var method: String = "POST"
    @State private var showToken = false
    @State private var response: APIResponse?
    @State private var failure: String?
    @State private var inFlight = false
    @State private var history: [String] = []

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE"]

    private struct Preset: Identifiable {
        let id = UUID()
        let label: String
        let method: String
        let path: String
    }

    /// Paths recovered from the vendor binary, or kept because they answered.
    /// Only the refresh route is confirmed against the live API; the rest are the
    /// naming pattern, and the console reports honestly whether each one exists.
    private let presets: [Preset] = [
        Preset(label: "refresh token · confirmed", method: "POST", path: "/api/v1/auth/token/refresh"),
        Preset(label: "base", method: "GET", path: "/api/v1/"),
        Preset(label: "end rent · fragment", method: "POST", path: "/api/v1/rides/end-rent"),
        Preset(label: "pause · fragment", method: "POST", path: "/api/v1/rides/pause"),
        Preset(label: "resume · fragment", method: "POST", path: "/api/v1/rides/resume"),
        Preset(label: "status · fragment", method: "GET", path: "/api/v1/rides/status")
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    warningCard
                    tokenCard
                    requestCard
                    presetsCard
                    responseCard
                    if !history.isEmpty { historyCard }
                }
                .padding(16)
            }
        }
        .navigationTitle("api console")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    token = ""
                    response = nil
                    failure = nil
                    history = []
                }
                .foregroundStyle(Theme.textDim)
            }
        }
    }

    // MARK: - cards

    private var warningCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill").foregroundStyle(Theme.amber)
                    Text("the last mile is your token")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                }
                Text("Every route on this API answers 401 without a bearer token, and that token is minted by an SMS to your phone. Nothing here can substitute for it. Paste yours below and every call becomes real.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tokenCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                field("bearer token", text: $token, secure: !showToken, mono: true)

                HStack(spacing: 10) {
                    Button {
                        showToken.toggle()
                    } label: {
                        Label(showToken ? "hide" : "show", systemImage: showToken ? "eye.slash" : "eye")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Text(token.isEmpty ? "not set" : "\(token.count) chars")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(token.isEmpty ? Theme.danger : Theme.lime)
                }

                Text("Stored in this device's preferences so you don't retype it. Clear it when you're finished.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private var requestCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                field("base url", text: $base, mono: true)

                HStack(spacing: 10) {
                    Menu {
                        ForEach(methods, id: \.self) { m in
                            Button(m) { method = m }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(method)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.lime)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textDim)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bg))
                    }

                    TextField("", text: $path, prompt: Text("/api/v1/...").foregroundStyle(Theme.textDim))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bg))
                }

                if method != "GET" {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("body")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textDim)
                            .textCase(.uppercase)
                        TextEditor(text: $requestBody)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .scrollContentBackground(.hidden)
                            .frame(height: 90)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bg))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Button {
                    Task { await fire() }
                } label: {
                    HStack(spacing: 8) {
                        if inFlight {
                            ProgressView().tint(Theme.bg).scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill").font(.system(size: 13, weight: .bold))
                        }
                        Text(inFlight ? "sending…" : "Send")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(inFlight ? Theme.stroke : Theme.lime))
                }
                .disabled(inFlight)
            }
        }
    }

    private var presetsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("presets")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .textCase(.uppercase)
                Text("Only the refresh route is confirmed against the live API. The others are the naming pattern read out of their binary — the console reports honestly whether each one exists.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(presets) { preset in
                    Button {
                        method = preset.method
                        path = preset.path
                    } label: {
                        HStack(spacing: 8) {
                            Text(preset.method)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.lime)
                                .frame(width: 46, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.text.opacity(0.9))
                                Text(preset.label)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var responseCard: some View {
        if let failure {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("request failed")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.danger)
                    Text(failure)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.text.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if let response {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("\(response.status)")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(response.isSuccess ? Theme.lime : Theme.amber)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(response.verdict)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text(String(format: "%.0f ms", response.elapsed * 1000))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                    }

                    if let ctype = response.headers["Content-Type"] {
                        Text(ctype)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }

                    Divider().overlay(Theme.stroke)

                    Text(APIClient.pretty(response.body))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.text.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("this session")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .textCase(.uppercase)
                ForEach(Array(history.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.text.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, secure: Bool = false, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textDim)
                .textCase(.uppercase)

            Group {
                if secure {
                    SecureField("", text: text,
                                prompt: Text("paste your bearer token").foregroundStyle(Theme.textDim))
                } else {
                    TextField("", text: text)
                }
            }
            .font(.system(size: 12, design: mono ? .monospaced : .default))
            .foregroundStyle(Theme.text)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.bg))
        }
    }

    // MARK: - actions

    private func fire() async {
        inFlight = true
        failure = nil
        defer { inFlight = false }

        do {
            let result = try await client.send(method: method,
                                               base: base,
                                               path: path,
                                               token: token,
                                               body: requestBody)
            response = result
            let stamp = Date().formatted(date: .omitted, time: .standard)
            history.insert("\(stamp)  \(method) \(path) → \(result.status)  \(result.verdict)", at: 0)
        } catch {
            failure = error.localizedDescription
            response = nil
        }
    }
}
