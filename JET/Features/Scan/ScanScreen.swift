import SwiftUI
import AVFoundation
import UIKit

struct ScanScreen: View {
    @EnvironmentObject private var store: RideStore

    @State private var manualCode = ""
    @State private var resolved: Scooter?
    @State private var missed = false
    @State private var showUnlock = false
    @State private var lastScan: String?
    @State private var authorized: Bool = true

    var body: some View {
        ZStack {
            QRScannerView(onCode: handle)
                .ignoresSafeArea()

            Color.black.opacity(0.35).ignoresSafeArea().allowsHitTesting(false)

            reticle.allowsHitTesting(false)

            VStack {
                Spacer()
                bottomPanel
            }
        }
        .sheet(isPresented: $showUnlock) {
            if let scooter = resolved {
                UnlockSheet(scooter: scooter)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("no scooter with that code", isPresented: $missed) {
            Button("ok", role: .cancel) {}
        }
        .onAppear(perform: requestCamera)
    }

    private var reticle: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: 3, dash: [14, 10]))
                .frame(width: 250, height: 250)
                .shadow(color: Theme.lime.opacity(0.5), radius: 16)
            Text("point at the QR code on the handlebar")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.top, 18)
            Spacer()
            Spacer()
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if !authorized {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                    Text("camera access is off — enable it in settings, or type the code below")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.amber)
                .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                TextField("", text: $manualCode, prompt: Text("SK-8F31A2").foregroundStyle(Theme.textDim))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceHi))

                Button {
                    handle(manualCode)
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
                }
            }

            if let lastScan {
                Text("last scan: \(lastScan)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface.opacity(0.96))
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - logic

    /// Accepts a bare id, a `jet:` prefixed deep link, or a URL with a code param.
    private func handle(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let candidate: String
        if let range = trimmed.range(of: "jet:", options: .caseInsensitive) {
            let tail = String(trimmed[range.upperBound...])
            candidate = tail.components(separatedBy: "&").first ?? tail
        } else if trimmed.contains("/") {
            let pieces = trimmed.components(separatedBy: "/")
            candidate = pieces.last ?? trimmed
        } else {
            candidate = trimmed
        }

        let cleaned = candidate.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        lastScan = cleaned

        guard let scooter = Scooter.find(cleaned) else {
            missed = true
            return
        }

        resolved = scooter
        manualCode = ""
        showUnlock = true
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { authorized = granted }
            }
        default:
            authorized = false
        }
    }
}

/// Thin AVFoundation bridge. Metadata output only — no photo capture, no recording.
struct QRScannerView: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        context.coordinator.configure(on: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "com.kanha.jet.scanner")
        private let onCode: (String) -> Void
        private var lastValue: String?
        private var lastFire = Date.distantPast

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
            super.init()
        }

        func configure(on view: PreviewView) {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            session.beginConfiguration()
            session.sessionPreset = .high

            if session.canAddInput(input) { session.addInput(input) }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                output.metadataObjectTypes = [.qr]
            }
            session.commitConfiguration()

            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill

            queue.async {
                if !self.session.isRunning { self.session.startRunning() }
            }
        }

        func stop() {
            queue.async {
                if self.session.isRunning { self.session.stopRunning() }
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }

            // Debounce: the camera fires the same code many times per second.
            let now = Date()
            if value == lastValue && now.timeIntervalSince(lastFire) < 2.5 { return }
            lastValue = value
            lastFire = now
            onCode(value)
        }
    }
}
