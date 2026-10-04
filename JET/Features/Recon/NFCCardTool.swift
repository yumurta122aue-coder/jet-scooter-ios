import Foundation
import CoreNFC

/// NFC card inspection.
///
/// What this can and cannot do is decided by iOS, not by us, so the tool reports
/// the platform's answer instead of pretending:
///
///   - iPhone reads ISO 14443 (MIFARE Ultralight / Plus / DESFire, ISO 7816
///     smartcards), ISO 15693 vicinity tags and FeliCa. It can send raw APDUs
///     and raw MIFARE commands to those.
///   - **MIFARE Classic is not supported by Core NFC at all.** A Classic card
///     yields its UID and nothing else. Transit cards in this family are the
///     common case, and it is a platform limit, not a bug here.
///   - **Card emulation does not exist on iOS.** There is no HCE equivalent to
///     Android. A third-party app cannot make the phone present itself as a
///     card, cannot reach the Secure Element, and cannot behave like Apple Pay.
///   - NFCTagReaderSession also needs the NFC Tag Reading entitlement, which a
///     free Apple ID cannot sign. Without it the session will refuse to begin.
final class NFCCardTool: NSObject, ObservableObject {

    struct CardSummary: Equatable {
        var technology: String = "—"
        var identifier: String = "—"
        var detail: String = "—"
        var ndef: String?
    }

    @Published private(set) var lines: [String] = []
    @Published private(set) var summary: CardSummary?
    @Published private(set) var isReading = false
    @Published var rawCommand: String = "60"

    private var session: NFCTagReaderSession?
    private var connectedMiFare: NFCMiFareTag?

    var readingAvailable: Bool { NFCTagReaderSession.readingAvailable }

    // MARK: - control

    func start() {
        guard NFCTagReaderSession.readingAvailable else {
            note("this device cannot read NFC tags")
            return
        }

        summary = nil
        connectedMiFare = nil
        isReading = true
        note("session starting — iso14443 · iso15693 · iso18092")

        let session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092],
                                          delegate: self,
                                          queue: nil)
        guard let session else {
            isReading = false
            note("session refused — the NFC Tag Reading entitlement is missing from this build")
            return
        }
        session.alertMessage = "Hold the top of the iPhone against the card."
        self.session = session
        session.begin()
    }

    func stop() {
        session?.invalidate()
        session = nil
        connectedMiFare = nil
        isReading = false
    }

    /// Raw MIFARE command, e.g. 60 for GET_VERSION, 30 04 for a READ of block 4.
    func sendRawMifare() {
        guard let data = Data(hexString: rawCommand) else {
            note("'\(rawCommand)' is not valid hex")
            return
        }
        guard let tag = connectedMiFare else {
            note("no MIFARE tag connected")
            return
        }
        note("→ \(rawCommand.uppercased())")
        tag.sendMiFareCommand(commandPacket: data) { [weak self] response, error in
            guard let self else { return }
            if let error {
                self.note("   ← failed: \(error.localizedDescription)")
                return
            }
            self.note("   ← \(response.hexSpaced)")
        }
    }

    // MARK: - internals

    private func note(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        lines.append("\(stamp)  \(text)")
    }

    private func familyName(_ family: NFCMiFareFamily) -> String {
        switch family {
        case .ultralight: return "Ultralight / NTAG"
        case .plus:       return "Plus"
        case .desfire:    return "DESFire"
        default:          return "unknown (Classic is unsupported by iOS)"
        }
    }

    private func inspect(_ tag: NFCTag, session: NFCTagReaderSession) {
        var card = CardSummary()
        var ndefTag: NFCNDEFTag?

        switch tag {
        case .miFare(let mifare):
            connectedMiFare = mifare
            ndefTag = mifare
            card.technology = "MIFARE (ISO 14443-A)"
            card.identifier = mifare.identifier.hexSpaced
            card.detail = familyName(mifare.miFareFamily)
            note("MIFARE uid=\(mifare.identifier.hexSpaced) family=\(familyName(mifare.miFareFamily))")

            // GET_VERSION separates Ultralight from NTAG21x and friends.
            mifare.sendMiFareCommand(commandPacket: Data([0x60])) { [weak self] response, error in
                guard let self else { return }
                if let error {
                    self.note("   GET_VERSION failed: \(error.localizedDescription)")
                } else {
                    self.note("   GET_VERSION: \(response.hexSpaced)")
                }
            }

        case .iso7816(let iso):
            ndefTag = iso
            card.technology = "ISO 7816 smartcard"
            card.identifier = iso.identifier.hexSpaced
            card.detail = "selected AID \(iso.initialSelectedAID)"
            note("ISO7816 uid=\(iso.identifier.hexSpaced) aid=\(iso.initialSelectedAID)")

        case .iso15693(let vicinity):
            ndefTag = vicinity
            card.technology = "ISO 15693 vicinity"
            card.identifier = vicinity.identifier.hexSpaced
            card.detail = "manufacturer code \(vicinity.icManufacturerCode)"
            note("ISO15693 uid=\(vicinity.identifier.hexSpaced) mfr=\(vicinity.icManufacturerCode)")

        case .feliCa(let felica):
            ndefTag = felica
            card.technology = "FeliCa"
            card.identifier = felica.currentIDm.hexSpaced
            card.detail = "system \(felica.currentSystemCode.hexSpaced)"
            note("FeliCa idm=\(felica.currentIDm.hexSpaced)")

        @unknown default:
            card.technology = "unrecognised tag"
            note("unrecognised tag technology")
        }

        summary = card

        if let ndefTag {
            ndefTag.queryNDEFStatus { [weak self] status, capacity, error in
                guard let self else { return }
                if let error {
                    self.note("NDEF status failed: \(error.localizedDescription)")
                    return
                }
                let statusText: String
                switch status {
                case .notSupported: statusText = "not supported"
                case .readOnly:     statusText = "read-only"
                case .readWrite:    statusText = "read/write"
                default:            statusText = "unknown"
                }
                self.note("NDEF: \(statusText), capacity \(capacity) bytes")

                guard status != .notSupported else {
                    session.alertMessage = "Card read. No NDEF data."
                    session.invalidate()
                    return
                }

                ndefTag.readNDEF { [weak self] message, error in
                    guard let self else { return }
                    if let error {
                        self.note("NDEF read failed: \(error.localizedDescription)")
                    } else if let message, let record = message.records.first {
                        let payload = String(data: record.payload, encoding: .utf8) ?? record.payload.hexSpaced
                        self.summary?.ndef = payload
                        self.note("NDEF record: \(payload)")
                    } else {
                        self.note("NDEF: empty")
                    }
                    session.alertMessage = "Card read."
                    session.invalidate()
                }
            }
        } else {
            session.alertMessage = "Card read."
            session.invalidate()
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension NFCCardTool: NFCTagReaderSessionDelegate {

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        note("session active — present a card")
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        isReading = false
        connectedMiFare = nil
        if let readerError = error as? NFCReaderError,
           readerError.code == .readerSessionInvalidationErrorUserCanceled {
            note("session cancelled")
        } else if let readerError = error as? NFCReaderError,
                  readerError.code == .readerSessionInvalidationErrorSessionTimeout {
            note("session timed out")
        } else {
            note("session ended: \(error.localizedDescription)")
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "More than one card. Present a single card."
            session.restartPolling()
            return
        }

        note("tag detected — connecting")
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                session.invalidate(errorMessage: "Could not connect: \(error.localizedDescription)")
                return
            }
            self.inspect(tag, session: session)
        }
    }
}

// MARK: - helpers

extension Data {
    var hexSpaced: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    init?(hexString: String) {
        let cleaned = hexString.filter { $0.isHexDigit }
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var iterator = cleaned.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            guard let byte = UInt8(String([high, low]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self = Data(bytes)
    }
}
