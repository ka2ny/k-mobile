import CryptoKit
import Foundation
import Network

/// The UDP side of the native stream (contract v1, section 3): hello, decryption, FEC and loss.
final class StreamReceiver: @unchecked Sendable {
    struct Counters: Sendable { var frames = 0; var lost = 0; var dropped = 0; var bytes = 0 }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "k-mobile.stream.udp")
    private let key: SymmetricKey
    private let salt: [UInt8]
    private let session: String
    private var helloSeq: UInt32 = 0
    private var helloTimer: DispatchSourceTimer?
    private var lossTimer: DispatchSourceTimer?
    private var slots: [UInt32: Slot] = [:]
    private var newestShown: UInt32?
    private var lostReported: Set<UInt32> = []
    private(set) var counters = Counters()

    /// A whole access unit, in Annex B, ready for the decoder.
    var onFrame: (@Sendable (_ data: Data, _ keyframe: Bool, _ pts: UInt32) -> Void)?
    var onAudio: (@Sendable (_ opus: Data, _ pts: UInt32) -> Void)?
    var onLoss: (@Sendable (_ frame: UInt32) -> Void)?
    var onFailure: (@Sendable (String) -> Void)?

    private struct Slot {
        let first: Date
        let data: Int
        let parity: Int
        let keyframe: Bool
        let pts: UInt32
        var shards: [Int: [UInt8]] = [:]
        var lengths: [Int: Int] = [:]
    }

    init(host: String, port: Int, key: Data, salt: [UInt8], session: String) {
        self.key = SymmetricKey(data: key)
        self.salt = salt
        self.session = session
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        connection = NWConnection(to: endpoint, using: .udp)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sayHello()
                self.receive()
                self.startTimers()
            case .failed(let error): self.onFailure?("The picture's connection failed: \(error.localizedDescription)")
            default: break
            }
        }
        connection.start(queue: queue)
    }

    func stop() {
        queue.async { [self] in
            helloTimer?.cancel(); lossTimer?.cancel()
            connection.cancel()
            slots.removeAll()
        }
    }

    private func startTimers() {
        let hello = DispatchSource.makeTimerSource(queue: queue)
        hello.schedule(deadline: .now() + 2, repeating: 2)
        hello.setEventHandler { [weak self] in self?.sayHello() }
        hello.resume()
        helloTimer = hello
        let loss = DispatchSource.makeTimerSource(queue: queue)
        loss.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(10))
        loss.setEventHandler { [weak self] in self?.checkLoss() }
        loss.resume()
        lossTimer = loss
    }

    private func sayHello() {
        guard let body = try? JSONSerialization.data(withJSONObject: ["session": session]) else { return }
        let header = StreamPacketHeader(kind: .hello, seq: helloSeq, length: UInt16(body.count))
        helloSeq &+= 1
        let aad = header.encoded
        guard let nonceBytes = header.nonce(salt: salt), let nonce = try? AES.GCM.Nonce(data: nonceBytes),
              let sealed = try? AES.GCM.seal(body, using: key, nonce: nonce, authenticating: Data(aad)) else { return }
        var packet = Data(aad)
        packet.append(sealed.ciphertext)
        packet.append(sealed.tag)
        connection.send(content: packet, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self else { return }
            if let content { self.handle(Array(content)) }
            if error == nil { self.receive() }
        }
    }

    private func handle(_ bytes: [UInt8]) {
        // Anything that fails authentication is dropped silently and counted (contract section 3).
        guard let header = StreamPacketHeader(bytes), header.kind != .hello,
              let nonceBytes = header.nonce(salt: salt), let nonce = try? AES.GCM.Nonce(data: nonceBytes),
              let box = try? AES.GCM.SealedBox(
                nonce: nonce, ciphertext: Data(bytes[StreamPacketHeader.size..<(bytes.count - 16)]),
                tag: Data(bytes[(bytes.count - 16)...])),
              let plain = try? AES.GCM.open(box, using: key, authenticating: Data(bytes[0..<StreamPacketHeader.size]))
        else { counters.dropped += 1; return }
        counters.bytes += bytes.count
        switch header.kind {
        case .audio:
            onAudio?(plain.prefix(Int(header.length)), header.pts)
        case .video, .parity:
            shard(header, Array(plain))
        case .hello: break
        }
    }

    private func shard(_ h: StreamPacketHeader, _ plain: [UInt8]) {
        let frame = h.frame
        if let shown = newestShown, !isNewer(frame, than: shown) { return }  // a late frame
        var slot = slots[frame] ?? Slot(first: Date(), data: Int(h.data), parity: Int(h.parity),
                                        keyframe: h.keyframe, pts: h.pts)
        guard slot.data == Int(h.data), slot.parity == Int(h.parity) else { counters.dropped += 1; return }
        var padded = plain
        if padded.count < StreamFEC.shardSize { padded += [UInt8](repeating: 0, count: StreamFEC.shardSize - padded.count) }
        slot.shards[Int(h.index)] = Array(padded.prefix(StreamFEC.shardSize))
        if h.kind == .video { slot.lengths[Int(h.index)] = Int(h.length) }
        slots[frame] = slot
        tryAssemble(frame)
    }

    private func tryAssemble(_ frame: UInt32) {
        guard let slot = slots[frame], slot.shards.count >= slot.data,
              let data = StreamFEC.decode(slot.shards, data: slot.data, parity: slot.parity) else { return }
        // The last data shard carries the true length; the others are full.
        var unit = Data(capacity: slot.data * StreamFEC.shardSize)
        for (i, shard) in data.enumerated() {
            let length = i == slot.data - 1 ? (slot.lengths[i] ?? trimmedLength(shard)) : StreamFEC.shardSize
            unit.append(contentsOf: shard.prefix(length))
        }
        slots[frame] = nil
        // Everything older than a decoded frame is now stale.
        for old in slots.keys where !isNewer(old, than: frame) { slots[old] = nil }
        newestShown = frame
        lostReported = lostReported.filter { isNewer($0, than: frame) }
        counters.frames += 1
        onFrame?(unit, slot.keyframe, slot.pts)
    }

    /// A last shard rebuilt by FEC has no length of its own: trailing zero padding is trimmed by the decoder.
    private func trimmedLength(_ shard: [UInt8]) -> Int {
        var n = shard.count
        while n > 0 && shard[n - 1] == 0 { n -= 1 }
        return n
    }

    private func checkLoss() {
        let now = Date()
        for (frame, slot) in slots where now.timeIntervalSince(slot.first) > 0.05 {
            slots[frame] = nil
            counters.lost += 1
            if lostReported.insert(frame).inserted { onLoss?(frame) }
        }
    }

    private func isNewer(_ a: UInt32, than b: UInt32) -> Bool { a != b && (a &- b) < 0x8000_0000 }
}
