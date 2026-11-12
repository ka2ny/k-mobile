import AVFoundation
import Foundation

/// Opus, 48 kHz stereo, 10 ms a packet (contract v1, section 3, audio), played after a 40 ms buffer.
final class StreamAudio: @unchecked Sendable {
    private let queue = DispatchQueue(label: "k-mobile.stream.audio")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pcm = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private let opus: AVAudioFormat
    private let converter: AVAudioConverter?
    private var pending: [AVAudioPCMBuffer] = []
    private var playing = false
    private(set) var problem: String?

    init() {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 480, mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        opus = AVAudioFormat(streamDescription: &description)!
        converter = AVAudioConverter(from: opus, to: pcm)
        if converter == nil { problem = "This phone can't decode the computer's sound." }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: pcm)
    }

    func start() {
        queue.async { [self] in
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
            } catch {
                problem = "The sound couldn't start: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        queue.async { [self] in
            player.stop()
            engine.stop()
            pending.removeAll()
            playing = false
        }
    }

    func enqueue(_ packet: Data) {
        queue.async { [self] in
            guard let converter, engine.isRunning, let decoded = decode(packet, converter) else { return }
            if playing {
                player.scheduleBuffer(decoded)
                return
            }
            pending.append(decoded)
            if pending.count >= 4 {   // 40 ms
                for buffer in pending { player.scheduleBuffer(buffer) }
                pending.removeAll()
                player.play()
                playing = true
            }
        }
    }

    private func decode(_ packet: Data, _ converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let compressed = AVAudioCompressedBuffer(format: opus, packetCapacity: 1, maximumPacketSize: max(packet.count, 1))
        packet.withUnsafeBytes { raw in
            compressed.data.copyMemory(from: raw.baseAddress!, byteCount: packet.count)
        }
        compressed.byteLength = UInt32(packet.count)
        compressed.packetCount = 1
        compressed.packetDescriptions?.pointee = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))
        guard let out = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 480) else { return nil }
        var given = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if given { inputStatus.pointee = .noDataNow; return nil }
            given = true
            inputStatus.pointee = .haveData
            return compressed
        }
        return status == .error || out.frameLength == 0 ? nil : out
    }
}
