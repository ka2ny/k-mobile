import Foundation
import Network

/// Raw TCP bridge only. The board owns TLS, desktop authentication and certificate verification.
@MainActor
final class PhoneRelay {
    @MainActor private final class Stream {
        let id: UInt8
        let targets: [RelayTarget]
        var targetIndex = 0
        var connection: NWConnection?
        var deadline: Task<Void, Never>?
        var window = RelayWindow()
        var ready = false
        var announced = false
        var reading = false
        var pending: Data?
        var endAfterPending = false
        var queuedToTCP = 0
        init(id: UInt8, targets: [RelayTarget]) { self.id = id; self.targets = targets }
    }
    private var streams: [UInt8: Stream] = [:]
    private var control: [RelayFrame] = []
    private var flushing = false
    private let maximumPayload: Int
    private let send: (Data) -> Bool
    private let changed: (Int) -> Void
    private let verified: () -> Void
    private let failed: (String) -> Void

    init(maximumWrite: Int, send: @escaping (Data) -> Bool, verified: @escaping () -> Void, changed: @escaping (Int) -> Void,
         failed: @escaping (String) -> Void) {
        maximumPayload = min(maximumWrite - 2, 250)
        self.send = send; self.verified = verified; self.changed = changed; self.failed = failed
    }
    func receive(_ bytes: Data) {
        do {
            let frame = try RelayFrame(bytes)
            switch frame.kind {
            case .open:
                guard streams[frame.stream] == nil else { close(frame.stream); return }
                guard streams.count < 6 else { enqueue(.init(kind: .opened, stream: frame.stream, payload: Data([1]))); return }
                let targets = try RelayTarget.parse(frame.payload)
                verified()
                let stream = Stream(id: frame.stream, targets: targets)
                streams[frame.stream] = stream
                dial(stream)
            case .data:
                guard let stream = streams[frame.stream], stream.ready, let connection = stream.connection else {
                    enqueue(.init(kind: .close, stream: frame.stream)); return
                }
                guard stream.queuedToTCP + frame.payload.count <= 65_536 else { close(stream.id); return }
                stream.queuedToTCP += frame.payload.count
                connection.send(content: frame.payload, completion: .contentProcessed { [weak self, weak stream] error in
                    Task { @MainActor in
                        guard let self, let stream, self.streams[stream.id] === stream, stream.connection === connection else { return }
                        stream.queuedToTCP -= frame.payload.count
                        if error != nil { self.close(stream.id) }
                    }
                })
            case .credit:
                guard let stream = streams[frame.stream] else { return }
                do { try stream.window.grant(frame.credit) } catch { close(stream.id); return }
                flush()
            case .close: close(frame.stream, notify: false)
            case .opened, .hint: throw AccessoryFailure.invalid("The board sent an unexpected relay frame.")
            }
        } catch { stop(); failed(error.localizedDescription) }
    }
    func stop() {
        for stream in streams.values { stream.deadline?.cancel(); stream.connection?.cancel() }
        streams.removeAll(); control.removeAll(); changed(0)
    }
    private func dial(_ stream: Stream) {
        guard streams[stream.id] === stream else { return }
        guard stream.targetIndex < stream.targets.count else {
            close(stream.id, notify: false)
            enqueue(.init(kind: .opened, stream: stream.id, payload: Data([1])))
            return
        }
        let target = stream.targets[stream.targetIndex]
        stream.targetIndex += 1
        guard let port = NWEndpoint.Port(rawValue: target.port) else { close(stream.id); return }
        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: .tcp)
        stream.connection = connection
        connection.stateUpdateHandler = { [weak self, weak stream] state in
            Task { @MainActor in
                guard let self, let stream, self.streams[stream.id] === stream, stream.connection === connection else { return }
                switch state {
                case .ready:
                    stream.deadline?.cancel()
                    stream.ready = true
                    self.changed(self.streams.values.filter { $0.ready }.count)
                    self.flush()
                case .failed:
                    if stream.ready { self.close(stream.id) } else { self.next(stream, connection: connection) }
                default: break
                }
            }
        }
        stream.deadline = Task { [weak self, weak stream] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard let self, let stream, self.streams[stream.id] === stream, stream.connection === connection, !stream.ready else { return }
            self.next(stream, connection: connection)
        }
        connection.start(queue: .main)
    }
    private func next(_ stream: Stream, connection: NWConnection) {
        stream.deadline?.cancel()
        stream.connection = nil
        connection.cancel()
        dial(stream)
    }
    func flush() {
        guard !flushing, maximumPayload > 0 else { return }
        flushing = true
        defer { flushing = false }
        var sent = 0
        // Bound work on the UI actor; each round gives every stream a turn.
        while sent < 16 {
            while sent < 16, let first = control.first {
                guard send(first.encoded) else { return }
                control.removeFirst()
                sent += 1
            }
            if sent >= 16 { break }
            var progressed = false
            for stream in Array(streams.values) where stream.ready {
                if sent >= 16 { break }
                if !stream.announced {
                    guard send(RelayFrame(kind: .opened, stream: stream.id, payload: Data([0])).encoded) else { return }
                    stream.announced = true
                    sent += 1; progressed = true
                }
                if sent >= 16 { break }
                if let pending = stream.pending {
                    let chunk = Data(pending.prefix(maximumPayload))
                    guard send(RelayFrame(kind: .data, stream: stream.id, payload: chunk).encoded) else { return }
                    do { try stream.window.consume(chunk.count) } catch { close(stream.id); continue }
                    stream.pending = pending.count == chunk.count ? nil : Data(pending.dropFirst(chunk.count))
                    sent += 1; progressed = true
                    if stream.pending == nil && stream.endAfterPending { close(stream.id); continue }
                }
                read(stream)
            }
            if !progressed && control.isEmpty { return }
        }
        Task { [weak self] in
            await Task.yield()
            self?.flush()
        }
    }
    private func read(_ stream: Stream) {
        guard !stream.reading, stream.pending == nil, stream.window.available > 0,
              let connection = stream.connection else { return }
        stream.reading = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(4096, stream.window.available)) { [weak self, weak stream] data, _, complete, error in
            Task { @MainActor in
                guard let self, let stream, self.streams[stream.id] === stream, stream.connection === connection else { return }
                stream.reading = false
                if let data, !data.isEmpty {
                    stream.pending = data
                    stream.endAfterPending = complete || error != nil
                    self.flush()
                } else if complete || error != nil { self.close(stream.id) }
                else { self.close(stream.id) }
            }
        }
    }
    private func close(_ id: UInt8, notify: Bool = true) {
        let stream = streams.removeValue(forKey: id)
        stream?.deadline?.cancel(); stream?.connection?.cancel()
        changed(streams.values.filter { $0.ready }.count)
        if notify { enqueue(.init(kind: .close, stream: id)) }
    }
    private func enqueue(_ frame: RelayFrame) {
        guard control.count < 32 else { stop(); failed("Bluetooth relay stalled. Reconnect the board."); return }
        control.append(frame)
        flush()
    }
}
