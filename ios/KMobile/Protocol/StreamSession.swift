import Foundation
import Network
import Security

/// Native stream contract v1, setup and control (k-mobile native-stream-contract.md, sections 1 and 2).
enum StreamWire {
    struct Request: Encodable, Sendable {
        let w: Int
        let h: Int
        let scale: Double
        let fps: Int
        let codecs: [String]
        let audio: Bool
        let screen: String
        let auto: Bool
        let rotate: Int
    }

    struct Offer: Decodable, Sendable {
        struct FEC: Decodable, Sendable { let percent: Int; let min: Int }
        let ok: Bool?
        let session: String
        let codec: String
        let w: Int
        let h: Int
        let fps: Int
        let bitrate: Int?
        let port: Int
        let key: String
        let salt: String
        let control: String?
        let screen: String?
        let why: String?
        let fec: FEC?

        var keyBytes: Data? { Data(base64Encoded: key).flatMap { $0.count == 16 ? $0 : nil } }
        var saltBytes: [UInt8]? { Data(base64Encoded: salt).flatMap { $0.count == 4 ? Array($0) : nil } }
    }
}

/// Words for every way setup or the session can stop, said beside the Connect button.
enum StreamWords {
    static func setup(_ error: Error) -> String {
        switch error as? GatewayError {
        case .http(401, _), .needsPairing: return "This phone isn't paired with the computer any more. Pair it again."
        case .http(403, let message), .needsControl(let message):
            if message.lowercased().contains("privacy") {
                return "The computer stopped everything for privacy. Resume it on the computer."
            }
            return "This phone can only watch. Ask for full control to use the screen."
        case .http(409, let message):
            let m = message.lowercased()
            if m.contains("taken") { return "You took the desktop back on the computer. Press Connect to use it again." }
            if m.contains("question") { return "The computer is asking you something. Answer it there first." }
            return "Another device is showing the desktop. Connect again to take it over."
        case .http(503, _): return "The computer's remote screen isn't on. Turn on Remote in its Settings."
        case .http(_, let message): return message.isEmpty ? "The computer refused the stream." : message
        case .certificateMismatch: return "The computer's certificate changed. Pair this phone again."
        default: return AssistantModel.words(error)
        }
    }
}

/// The TLS control channel: 4-byte big-endian length, then JSON, at most 64 KB a frame.
final class StreamControl: @unchecked Sendable {
    typealias Message = [String: Any]
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "k-mobile.stream.control")
    private var pinger: DispatchSourceTimer?
    private var pingNumber = 0
    private var sentPings: [Int: Date] = [:]
    private(set) var rtt: Double = 0
    var onMessage: (@Sendable (Message) -> Void)?
    var onEnd: (@Sendable (String) -> Void)?
    private var ended = false

    init(host: String, port: Int, pinnedDigest: String?) {
        let tls = NWProtocolTLS.Options()
        if let pin = pinnedDigest {
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first
                else { complete(false); return }
                complete(ServerTrust.digest(SecCertificateCopyData(leaf) as Data) == pin)
            }, DispatchQueue(label: "k-mobile.stream.trust"))
        }
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        connection = NWConnection(to: endpoint, using: parameters)
    }

    func start(session: String, token: String) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.send(["t": "auth", "session": session, "token": token])
                self.receive()
                self.startPings()
            case .failed(let error): self.finish("The control connection failed: \(error.localizedDescription)")
            case .cancelled: self.finish("")
            default: break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ message: Message) {
        guard let body = try? JSONSerialization.data(withJSONObject: message), body.count <= 65_536 else { return }
        var frame = Data([UInt8(body.count >> 24 & 0xff), UInt8(body.count >> 16 & 0xff),
                          UInt8(body.count >> 8 & 0xff), UInt8(body.count & 0xff)])
        frame.append(body)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    func stop(bye: Bool = true) {
        queue.async { [self] in
            if bye && !ended { send(["t": "bye"]) }
            pinger?.cancel()
            connection.cancel()
        }
    }

    private func startPings() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.pingNumber += 1
            self.sentPings[self.pingNumber] = Date()
            self.send(["t": "ping", "n": self.pingNumber])
        }
        timer.resume()
        pinger = timer
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] head, _, done, error in
            guard let self else { return }
            guard error == nil, let head, head.count == 4 else {
                self.finish(done ? "The computer ended the stream." : "The control connection broke.")
                return
            }
            let bytes = Array(head)
            let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            guard length > 0, length <= 65_536 else { self.finish("The computer sent a frame the phone can't read."); return }
            self.connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                guard error == nil, let body,
                      let message = (try? JSONSerialization.jsonObject(with: body)) as? Message else {
                    self.finish("The control connection broke.")
                    return
                }
                if message["t"] as? String == "pong", let n = message["n"] as? Int, let sent = self.sentPings[n] {
                    self.rtt = Date().timeIntervalSince(sent) * 1000
                    self.sentPings[n] = nil
                }
                self.onMessage?(message)
                self.receive()
            }
        }
    }

    private func finish(_ why: String) {
        guard !ended else { return }
        ended = true
        pinger?.cancel()
        connection.cancel()
        onEnd?(why)
    }
}
