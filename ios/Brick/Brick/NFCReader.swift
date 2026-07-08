import CoreNFC
import Foundation

final class NFCReader: NSObject, NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    private var completion: ((Result<String, Error>) -> Void)?

    func scan(completion: @escaping (Result<String, Error>) -> Void) {
        guard NFCTagReaderSession.readingAvailable else {
            completion(.failure(NFCReaderError.unavailable))
            return
        }

        self.completion = completion
        guard let session = NFCTagReaderSession(
            pollingOption: [.iso14443, .iso15693],
            delegate: self,
            queue: nil
        ) else {
            completion(.failure(NFCReaderError.unavailable))
            return
        }
        session.alertMessage = "Hold your iPhone near the Blank NFC tag."
        self.session = session
        session.begin()
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        completion?(.failure(error))
        completion = nil
        self.session = nil
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No NFC tag found.")
            return
        }

        let identifier: Data
        switch tag {
        case .miFare(let miFareTag):
            identifier = miFareTag.identifier
        case .iso7816(let iso7816Tag):
            identifier = iso7816Tag.identifier
        case .iso15693(let iso15693Tag):
            identifier = iso15693Tag.identifier
        case .feliCa(let feliCaTag):
            identifier = feliCaTag.currentIDm
        @unknown default:
            session.invalidate(errorMessage: "Unsupported NFC tag.")
            return
        }

        let uid = identifier.map { String(format: "%02X", $0) }.joined()
        session.alertMessage = "Blank tag detected."
        session.invalidate()
        completion?(.success(uid))
        completion = nil
        self.session = nil
    }
}

enum NFCReaderError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "NFC tag reading is not available on this device."
        }
    }
}
