import AVFoundation
import CoreMedia
import Foundation

/// Turns Annex B access units into sample buffers on a display layer (contract v1, section 3, video).
/// Every keyframe carries its parameter sets inline; the format is rebuilt from them.
final class StreamVideo: @unchecked Sendable {
    @MainActor let layer: AVSampleBufferDisplayLayer
    private let renderer: AVSampleBufferVideoRenderer
    private let queue = DispatchQueue(label: "k-mobile.stream.video")
    private var codec: String
    private var format: CMVideoFormatDescription?
    private var waitingForKeyframe = true
    /// Asks the computer for a keyframe (the decoder lost its place).
    var onNeedKeyframe: (@Sendable () -> Void)?

    @MainActor init(codec: String) {
        self.codec = codec
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        self.layer = layer
        renderer = layer.sampleBufferRenderer
    }

    /// After a `codec` message: drop the format and wait for the next keyframe.
    func reset(codec: String) {
        queue.async { [self] in
            self.codec = codec
            format = nil
            waitingForKeyframe = true
            renderer.flush()
        }
    }

    func enqueue(_ frame: Data, keyframe: Bool, pts: UInt32) {
        queue.async { [self] in
            if renderer.status == .failed {
                renderer.flush()
                format = nil
                waitingForKeyframe = true
                onNeedKeyframe?()
            }
            let units = Self.nalUnits(frame)
            if keyframe, let made = makeFormat(units) { format = made; waitingForKeyframe = false }
            guard !waitingForKeyframe, let format else { return }
            let slices = units.filter { !isParameterSet($0) }
            guard !slices.isEmpty, let buffer = sampleBuffer(slices, format: format, pts: pts) else { return }
            renderer.enqueue(buffer)
        }
    }

    // MARK: Annex B

    /// Splits on 3- or 4-byte start codes; the last unit loses its zero padding.
    static func nalUnits(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(at: Int, code: Int)] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0 {
                if bytes[i + 2] == 1 { starts.append((i, 3)); i += 3; continue }
                if i + 3 < bytes.count, bytes[i + 2] == 0, bytes[i + 3] == 1 { starts.append((i, 4)); i += 4; continue }
            }
            i += 1
        }
        var units: [Data] = []
        for (n, start) in starts.enumerated() {
            let from = start.at + start.code
            var to = n + 1 < starts.count ? starts[n + 1].at : bytes.count
            if n + 1 == starts.count { while to > from, bytes[to - 1] == 0 { to -= 1 } }
            if to > from { units.append(Data(bytes[from..<to])) }
        }
        return units
    }

    private func nalType(_ unit: Data) -> Int {
        guard let first = unit.first else { return -1 }
        return codec == "hevc" ? Int(first >> 1) & 0x3F : Int(first) & 0x1F
    }

    private func isParameterSet(_ unit: Data) -> Bool {
        let t = nalType(unit)
        return codec == "hevc" ? (32...34).contains(t) : (t == 7 || t == 8)
    }

    private func makeFormat(_ units: [Data]) -> CMVideoFormatDescription? {
        var sets: [Data] = []
        if codec == "hevc" {
            for wanted in [32, 33, 34] { if let u = units.first(where: { nalType($0) == wanted }) { sets.append(u) } }
            guard sets.count == 3 else { return nil }
        } else {
            for wanted in [7, 8] { if let u = units.first(where: { nalType($0) == wanted }) { sets.append(u) } }
            guard sets.count == 2 else { return nil }
        }
        let arrays = sets.map { [UInt8]($0) }
        var result: CMVideoFormatDescription?
        let status: OSStatus = arrays[0].withUnsafeBufferPointer { a in
            arrays[1].withUnsafeBufferPointer { b in
                if codec == "hevc" {
                    return arrays[2].withUnsafeBufferPointer { c in
                        let pointers = [a.baseAddress!, b.baseAddress!, c.baseAddress!]
                        let sizes = arrays.map(\.count)
                        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                            allocator: kCFAllocatorDefault, parameterSetCount: 3, parameterSetPointers: pointers,
                            parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil,
                            formatDescriptionOut: &result)
                    }
                }
                let pointers = [a.baseAddress!, b.baseAddress!]
                let sizes = arrays.map(\.count)
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &result)
            }
        }
        return status == noErr ? result : nil
    }

    private func sampleBuffer(_ units: [Data], format: CMVideoFormatDescription, pts: UInt32) -> CMSampleBuffer? {
        var avcc = Data()
        for unit in units {
            let n = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: n) { avcc.append(contentsOf: $0) }
            avcc.append(unit)
        }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: avcc.count, flags: 0, blockBufferOut: &block) == noErr,
            let block else { return nil }
        let copied = avcc.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                          dataLength: avcc.count)
        }
        guard copied == noErr else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: 90_000),
                                        decodeTimeStamp: .invalid)
        var size = avcc.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sample) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
