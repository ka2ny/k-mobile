import Foundation
import Testing
@testable import KMobileProtocol

/// The shared vector (also /mnt/project-files/k-mobile/fec-vector.json): the computer's encoder must give the same parity.
struct StreamFECTests {
    static let data: [[UInt8]] = (0..<3).map { (column: Int) -> [UInt8] in
        let start = column * 37 + 1
        return (0..<8).map { (index: Int) -> UInt8 in
            let value = start + index * 11
            return UInt8(value & 0xff)
        }
    }
    static let parity: [[UInt8]] = [
        [172, 196, 114, 223, 69, 193, 115, 21],
        [121, 70, 170, 116, 151, 113, 208, 239],
    ]

    @Test func vectorData() {
        #expect(Self.data[0] == [1, 12, 23, 34, 45, 56, 67, 78])
        #expect(Self.data[2] == [75, 86, 97, 108, 119, 130, 141, 152])
    }

    @Test func encodesTheVector() { #expect(StreamFEC.encode(Self.data, parity: 2) == Self.parity) }

    @Test(arguments: [[0, 3, 4], [1, 2, 4], [2, 3, 4], [0, 1, 3], [0, 1, 2]])
    func decodesFromAnyThree(_ have: [Int]) {
        let all = Self.data + Self.parity
        var shards: [Int: [UInt8]] = [:]
        for i in have { shards[i] = all[i] }
        #expect(StreamFEC.decode(shards, data: 3, parity: 2) == Self.data)
    }

    @Test func refusesTooFewOrMalformed() {
        #expect(StreamFEC.decode([0: Self.data[0], 4: Self.parity[1]], data: 3, parity: 2) == nil)
        #expect(StreamFEC.decode([0: Self.data[0], 1: [1, 2], 3: Self.parity[0]], data: 3, parity: 2) == nil)
        #expect(StreamFEC.decode([:], data: 0, parity: 0) == nil)
        #expect(StreamFEC.decode([:], data: 200, parity: 100) == nil)
    }

    @Test func largerFrameSurvivesLoss() {
        let k = 20
        let shards: [[UInt8]] = (0..<k).map { (column: Int) -> [UInt8] in
            let start = column &* 131
            return (0..<StreamFEC.shardSize).map { (index: Int) -> UInt8 in
                UInt8(truncatingIfNeeded: start &+ index &* 7)
            }
        }
        let p = StreamFEC.parityCount(data: k, percent: 20, min: 2)
        #expect(p == 4)
        let par = StreamFEC.encode(shards, parity: p)
        var got: [Int: [UInt8]] = [:]
        for (i, s) in (shards + par).enumerated() where ![1, 5, 9, 17].contains(i) { got[i] = s }
        #expect(StreamFEC.decode(got, data: k, parity: p) == shards)
    }

    @Test func parityCounts() {
        #expect(StreamFEC.parityCount(data: 1, percent: 20, min: 2) == 2)
        #expect(StreamFEC.parityCount(data: 11, percent: 20, min: 2) == 3)
        #expect(StreamFEC.parityCount(data: 250, percent: 20, min: 2) == 5)
        #expect(StreamFEC.parityCount(data: 255, percent: 20, min: 2) == 0)
    }

    @Test func headerRoundTrip() throws {
        let h = StreamPacketHeader(kind: .video, keyframe: true, lastOfGroup: false, seq: 0x0102_0304, frame: 77,
                                   index: 4, data: 3, parity: 2, pts: 90000, length: 1152)
        let bytes = h.encoded
        #expect(bytes.count == StreamPacketHeader.size)
        #expect(Array(bytes.prefix(4)) == [0x4B, 1, 1, 1])
        let parsed = try #require(StreamPacketHeader(bytes + [UInt8](repeating: 0, count: 16)))
        #expect(parsed == h)
        #expect(h.nonce(salt: [9, 8, 7, 6]) == [9, 8, 7, 6, 1, 0, 0, 0, 1, 2, 3, 4])
        #expect(h.nonce(salt: [1]) == nil)
    }

    @Test func headerRejections() {
        let good = StreamPacketHeader(kind: .audio, seq: 1, length: 100).encoded + [UInt8](repeating: 0, count: 16)
        #expect(StreamPacketHeader(good) != nil)
        func bad(_ change: (inout [UInt8]) -> Void) -> Bool { var b = good; change(&b); return StreamPacketHeader(b) == nil }
        #expect(bad { $0[0] = 0x4C })
        #expect(bad { $0[1] = 2 })
        #expect(bad { $0[2] = 9 })
        #expect(bad { $0[3] = 4 })
        #expect(bad { $0[14] = 0; $0[15] = 0 })
        #expect(bad { $0[12] = 0; $0[13] = 1 })
        #expect(bad { $0[22] = 0x04; $0[23] = 0x81 })
        #expect(bad { $0.removeLast() })
    }
}
