import AVFoundation
import SwiftUI
import UIKit

/// The computer's screen, streamed natively (contract v1): setup over HTTPS, control over TLS, media over UDP.
@MainActor @Observable
final class RemoteStreamModel {
    enum Phase: Equatable { case idle, starting, live, ended }

    private(set) var phase: Phase = .idle
    /// Said beside the Connect button: why it stopped, or what it waits for.
    private(set) var note: String?
    private(set) var held = false
    private(set) var stats = ""
    private(set) var size = CGSize(width: 16, height: 9)
    private(set) var video: StreamVideo?

    private var control: StreamControl?
    private var receiver: StreamReceiver?
    private var audio: StreamAudio?
    private var statsTask: Task<Void, Never>?
    private var lastFrames = 0
    private var lastBytes = 0
    private var restarts = 0

    func connect(_ app: AppModel, screen: CGSize, scale: CGFloat) async {
        guard phase != .starting else { return }
        guard let gateway = app.gateway, let host = app.selected?.origin.host(), let token = gateway.deviceToken else {
            note = "The computer isn't reachable right now. Check that it's on and on your tailnet."
            phase = .ended
            return
        }
        phase = .starting
        note = "Asking the computer for its screen…"
        let request = StreamWire.Request(
            w: Int(screen.width), h: Int(screen.height), scale: Double(scale), fps: 60,
            codecs: ["hevc", "h264"], audio: true, screen: "phone", auto: false, rotate: 0)
        let offer: StreamWire.Offer
        do {
            offer = try await gateway.send("/api/native/stream", json: request, as: StreamWire.Offer.self)
        } catch {
            note = StreamWords.setup(error)
            phase = .ended
            return
        }
        guard let key = offer.keyBytes, let salt = offer.saltBytes else {
            note = "The computer sent a stream key the phone can't read. Update k-hole on the computer."
            phase = .ended
            return
        }
        start(offer: offer, host: host, token: token, key: key, salt: salt, pin: gateway.pinnedDigest, app: app,
              screen: screen, scale: scale)
    }

    private func start(offer: StreamWire.Offer, host: String, token: String, key: Data, salt: [UInt8], pin: String?,
                       app: AppModel, screen: CGSize, scale: CGFloat) {
        let video = StreamVideo(codec: offer.codec)
        let audio = StreamAudio()
        let control = StreamControl(host: host, port: offer.port, pinnedDigest: pin)
        let receiver = StreamReceiver(host: host, port: offer.port, key: key, salt: salt, session: offer.session)
        size = CGSize(width: offer.w, height: offer.h)

        video.onNeedKeyframe = { [weak control] in control?.send(["t": "keyframe"]) }
        receiver.onFrame = { [weak video] data, keyframe, pts in video?.enqueue(data, keyframe: keyframe, pts: pts) }
        receiver.onAudio = { [weak audio] packet, _ in audio?.enqueue(packet) }
        receiver.onLoss = { [weak control] frame in control?.send(["t": "loss", "frame": Int(frame)]) }
        receiver.onFailure = { [weak self] why in Task { @MainActor in self?.end(why) } }
        control.onEnd = { [weak self] why in Task { @MainActor in self?.end(why.isEmpty ? nil : why) } }
        control.onMessage = { [weak self] message in
            let copy = message
            Task { @MainActor in self?.handle(copy, app: app, screen: screen, scale: scale) }
        }

        self.video = video
        self.audio = audio
        self.control = control
        self.receiver = receiver
        control.start(session: offer.session, token: token)
        receiver.start()
        audio.start()
        phase = .live
        note = nil
        if let why = offer.why, !why.isEmpty { note = why }
        startStats()
    }

    private func handle(_ message: StreamControl.Message, app: AppModel, screen: CGSize, scale: CGFloat) {
        switch message["t"] as? String {
        case "codec":
            if let codec = message["codec"] as? String { video?.reset(codec: codec) }
            if let w = message["w"] as? Int, let h = message["h"] as? Int { size = CGSize(width: w, height: h) }
        case "held":
            held = message["on"] as? Bool ?? false
        case "control":
            if let denied = message["denied"] as? String {
                note = denied == "keys"
                    ? "This phone can't type on the computer. Ask for full control in Settings > Remote on the computer."
                    : "This phone can only watch. Ask for full control on the computer."
            }
        case "restart":
            restarts += 1
            guard restarts <= 3 else { end("The computer kept restarting the stream. Press Connect to try again."); return }
            teardown(bye: false)
            Task { await connect(app, screen: screen, scale: scale) }
        case "bye":
            let why = message["why"] as? String ?? message["reason"] as? String
            end(why == "taken_back"
                ? "You took the desktop back on the computer. Press Connect to use it again."
                : "The computer ended the stream.")
        default: break
        }
    }

    private func startStats() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let receiver = self.receiver, let control = self.control else { return }
                let c = receiver.counters
                let fps = c.frames - self.lastFrames
                let kbps = (c.bytes - self.lastBytes) * 8 / 1000
                self.lastFrames = c.frames
                self.lastBytes = c.bytes
                let rtt = Int(control.rtt)
                control.send(["t": "stats", "rtt": rtt, "lost": c.lost, "fps": fps, "kbps": kbps])
                self.stats = "\(fps) fps · \(kbps) kbit/s · \(rtt) ms"
                if let problem = self.audio?.problem, self.note == nil { self.note = problem }
            }
        }
    }

    func disconnect() { end(nil) }

    private func end(_ why: String?) {
        guard phase != .ended || why != nil else { return }
        teardown(bye: true)
        phase = .ended
        if let why { note = why }
    }

    private func teardown(bye: Bool) {
        statsTask?.cancel()
        statsTask = nil
        control?.stop(bye: bye)
        receiver?.stop()
        audio?.stop()
        control = nil
        receiver = nil
        audio = nil
        video = nil
        held = false
    }

    // MARK: Input (normalised 0…1 in the stream's picture)

    func touches(_ points: [[Any]]) { control?.send(["t": "touch", "p": points]) }
    func type(_ text: String) {
        guard !text.isEmpty else { return }
        control?.send(["t": "text", "s": String(text.prefix(4096))])
    }
    func key(_ name: String) { control?.send(["t": "key", "k": name]) }
}

struct RemoteStreamView: View {
    @Environment(AppModel.self) private var app
    @State private var stream = RemoteStreamModel()
    @State private var typing = ""
    @FocusState private var keyboard: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let video = stream.video, stream.phase == .live {
                    StreamSurface(layer: video.layer, aspect: stream.size, onTouch: stream.touches)
                        .ignoresSafeArea(edges: .bottom)
                    overlay
                } else {
                    connectCard(geo.size)
                }
            }
        }
        .navigationTitle("Remote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(stream.phase == .live ? .hidden : .visible, for: .tabBar)
        .onDisappear { stream.disconnect() }
    }

    private func connectCard(_ size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            MobileIcon(.remote, size: 32)
            Text("Your computer's screen").font(.title2.weight(.medium))
            Text("Streamed straight to this phone, with its sound. Touch works like on the computer's screen.")
                .font(.callout).foregroundStyle(Design.muted)
            Button(stream.phase == .starting ? "Connecting…" : "Connect", systemImage: "play.fill") {
                Task { await stream.connect(app, screen: size, scale: UIScreen.main.scale) }
            }
            .buttonStyle(QuietProminentStyle())
            .disabled(stream.phase == .starting || app.gateway == nil)
            if let note = stream.note {
                Label(note, systemImage: stream.phase == .starting ? "hourglass" : "info.circle")
                    .font(.callout).foregroundStyle(Design.muted)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .quietCard()
        .padding(Design.inset)
    }

    private var overlay: some View {
        VStack {
            HStack(spacing: Design.gap) {
                Text(stream.stats).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Keyboard", systemImage: "keyboard") { keyboard.toggle() }
                    .labelStyle(.iconOnly)
                Button("Disconnect", systemImage: "xmark") { stream.disconnect() }
                    .labelStyle(.iconOnly)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, Design.inset)
            if stream.held {
                Label("The computer is asking something. Answer it there.", systemImage: "pause.circle")
                    .font(.footnote).padding(8).background(.ultraThinMaterial, in: Capsule())
            }
            if let note = stream.note {
                Text(note).font(.footnote).padding(8).background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            TextField("Type on the computer", text: $typing)
                .focused($keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .opacity(keyboard ? 1 : 0.01)
                .frame(height: keyboard ? nil : 1)
                .onChange(of: typing) { _, new in
                    guard !new.isEmpty else { return }
                    stream.type(new)
                    typing = ""
                }
                .onSubmit { stream.key("Return"); keyboard = true }
                .padding(.horizontal, Design.inset)
        }
    }
}

/// Hosts the display layer and turns finger touches into contract `touch` points, normalised to the picture.
private struct StreamSurface: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    let aspect: CGSize
    let onTouch: ([[Any]]) -> Void

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .black
        update(view)
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) { update(view) }

    private func update(_ view: SurfaceView) {
        if view.display !== layer {
            view.display?.removeFromSuperlayer()
            view.layer.addSublayer(layer)
            view.display = layer
        }
        view.aspect = aspect
        view.onTouch = onTouch
        view.setNeedsLayout()
    }

    final class SurfaceView: UIView {
        var display: AVSampleBufferDisplayLayer?
        var aspect = CGSize(width: 16, height: 9)
        var onTouch: (([[Any]]) -> Void)?
        private var ids: [ObjectIdentifier: Int] = [:]
        private var next = 1

        override func layoutSubviews() {
            super.layoutSubviews()
            display?.frame = bounds
        }

        /// The picture's rect inside the view (resizeAspect letterboxes it).
        private var picture: CGRect {
            guard aspect.width > 0, aspect.height > 0 else { return bounds }
            return AVMakeRect(aspectRatio: aspect, insideRect: bounds)
        }

        private func send(_ touches: Set<UITouch>, phase: String) {
            let rect = picture
            var points: [[Any]] = []
            for touch in touches {
                let key = ObjectIdentifier(touch)
                let id: Int
                if phase == "d" { id = next; next = next % 65535 + 1; ids[key] = id } else if let known = ids[key] { id = known } else { continue }
                if phase == "u" || phase == "c" { ids[key] = nil }
                let at = touch.location(in: self)
                let x = min(max((at.x - rect.minX) / max(rect.width, 1), 0), 1)
                let y = min(max((at.y - rect.minY) / max(rect.height, 1), 0), 1)
                points.append([id, phase, Double(x), Double(y)])
            }
            if !points.isEmpty { onTouch?(points) }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { send(touches, phase: "d") }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { send(touches, phase: "m") }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { send(touches, phase: "u") }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { send(touches, phase: "c") }
    }
}
