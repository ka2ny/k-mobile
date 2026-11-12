import Foundation

/// Reed-Solomon erasure coding for the native Remote stream (wire contract v1, appendix).
/// GF(2^8) with polynomial 0x11D and generator 2; parity row r for data shard c is
/// 1 / ((data + r) XOR c), a Cauchy matrix, so any `data` shards of a frame rebuild it.
public enum StreamFEC {
    public static let shardSize = 1152

    struct Field {
        var exp = [UInt8](repeating: 0, count: 512)
        var log = [Int](repeating: 0, count: 256)
        init() {
            var x = 1
            for i in 0..<255 {
                exp[i] = UInt8(x)
                log[x] = i
                x <<= 1
                if x & 0x100 != 0 { x ^= 0x11D }
            }
            for i in 255..<512 { exp[i] = exp[i - 255] }
        }
        func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
            a == 0 || b == 0 ? 0 : exp[log[Int(a)] + log[Int(b)]]
        }
        func inv(_ a: UInt8) -> UInt8 { exp[255 - log[Int(a)]] }
    }

    static let field = Field()

    /// How many parity shards a frame of `data` shards carries.
    public static func parityCount(data: Int, percent: Int, min: Int) -> Int {
        let wanted = Swift.max(min, (data * percent + 99) / 100)
        return Swift.max(0, Swift.min(wanted, 255 - data))
    }

    static func coefficient(row: Int, column: Int) -> UInt8 {
        field.inv(UInt8(truncatingIfNeeded: row ^ column))
    }

    /// Parity shards for equal-length data shards (the computer's side; used in tests).
    public static func encode(_ data: [[UInt8]], parity: Int) -> [[UInt8]] {
        guard let n = data.first?.count else { return [] }
        let k = data.count
        return (0..<parity).map { r in
            var out = [UInt8](repeating: 0, count: n)
            for c in 0..<k {
                let co = coefficient(row: k + r, column: c)
                for i in 0..<n { out[i] ^= field.mul(co, data[c][i]) }
            }
            return out
        }
    }

    /// Rebuilds the data shards from any `data` received shards, keyed by shard index
    /// (data shards first, then parity). Returns nil when too few arrived or the input is malformed.
    public static func decode(_ shards: [Int: [UInt8]], data k: Int, parity p: Int) -> [[UInt8]]? {
        guard k > 0, p >= 0, k + p <= 255 else { return nil }
        let indices = shards.keys.filter { $0 >= 0 && $0 < k + p }.sorted()
        guard indices.count >= k, let n = shards[indices[0]]?.count else { return nil }
        if (0..<k).allSatisfy({ shards[$0] != nil }) { return (0..<k).map { shards[$0]! } }
        let used = Array(indices.prefix(k))
        guard used.allSatisfy({ shards[$0]?.count == n }) else { return nil }
        // Rows of the generator matrix for the shards we have, augmented with the identity.
        var m: [[UInt8]] = used.enumerated().map { j, i in
            var row = [UInt8](repeating: 0, count: 2 * k)
            for c in 0..<k { row[c] = i < k ? (c == i ? 1 : 0) : coefficient(row: i, column: c) }
            row[k + j] = 1
            return row
        }
        for col in 0..<k {
            guard let pivot = (col..<k).first(where: { m[$0][col] != 0 }) else { return nil }
            m.swapAt(col, pivot)
            let f = field.inv(m[col][col])
            m[col] = m[col].map { field.mul(f, $0) }
            for r in 0..<k where r != col && m[r][col] != 0 {
                let g = m[r][col]
                for t in 0..<(2 * k) { m[r][t] ^= field.mul(g, m[col][t]) }
            }
        }
        return (0..<k).map { c in
            if let have = shards[c] { return have }
            var out = [UInt8](repeating: 0, count: n)
            for (j, i) in used.enumerated() {
                let co = m[c][k + j]
                guard co != 0, let shard = shards[i] else { continue }
                for t in 0..<n { out[t] ^= field.mul(co, shard[t]) }
            }
            return out
        }
    }
}

/// The 24-byte header of a native stream UDP packet (all integers big-endian). It is also
/// the AES-GCM associated data; the ciphertext and 16-byte tag follow it.
public struct StreamPacketHeader: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case hello = 0, video = 1, parity = 2, audio = 3 }
    public static let size = 24
    public static let magic: UInt8 = 0x4B
    public static let version: UInt8 = 1

    public var kind: Kind
    public var keyframe: Bool
    public var lastOfGroup: Bool
    public var seq: UInt32
    public var frame: UInt32
    public var index: UInt16
    public var data: UInt16
    public var parity: UInt16
    public var pts: UInt32
    public var length: UInt16

    public init(kind: Kind, keyframe: Bool = false, lastOfGroup: Bool = false, seq: UInt32, frame: UInt32 = 0,
                index: UInt16 = 0, data: UInt16 = 1, parity: UInt16 = 0, pts: UInt32 = 0, length: UInt16) {
        self.kind = kind; self.keyframe = keyframe; self.lastOfGroup = lastOfGroup; self.seq = seq; self.frame = frame
        self.index = index; self.data = data; self.parity = parity; self.pts = pts; self.length = length
    }

    /// Parses a packet's header; nil for anything that isn't a well-formed v1 header.
    public init?(_ bytes: [UInt8]) {
        guard bytes.count >= Self.size + 16, bytes[0] == Self.magic, bytes[1] == Self.version,
              let kind = Kind(rawValue: bytes[2]), bytes[3] & ~0x03 == 0 else { return nil }
        func u16(_ o: Int) -> UInt16 { UInt16(bytes[o]) << 8 | UInt16(bytes[o + 1]) }
        func u32(_ o: Int) -> UInt32 { UInt32(u16(o)) << 16 | UInt32(u16(o + 2)) }
        self.kind = kind
        keyframe = bytes[3] & 1 != 0
        lastOfGroup = bytes[3] & 2 != 0
        seq = u32(4); frame = u32(8); index = u16(12); data = u16(14); parity = u16(16); pts = u32(18); length = u16(22)
        guard data >= 1, Int(data) + Int(parity) <= 255, index < data + parity,
              Int(length) <= StreamFEC.shardSize else { return nil }
    }

    public var encoded: [UInt8] {
        var out: [UInt8] = [Self.magic, Self.version, kind.rawValue, (keyframe ? 1 : 0) | (lastOfGroup ? 2 : 0)]
        func put16(_ v: UInt16) { out += [UInt8(v >> 8), UInt8(v & 0xff)] }
        func put32(_ v: UInt32) { put16(UInt16(v >> 16)); put16(UInt16(v & 0xffff)) }
        put32(seq); put32(frame); put16(index); put16(data); put16(parity); put32(pts); put16(length)
        return out
    }

    /// salt(4) || type(1) || 0x000000 || seq(4): never reused within a session for a direction and type.
    public func nonce(salt: [UInt8]) -> [UInt8]? {
        guard salt.count == 4 else { return nil }
        return salt + [kind.rawValue, 0, 0, 0, UInt8(seq >> 24), UInt8((seq >> 16) & 0xff), UInt8((seq >> 8) & 0xff),
                       UInt8(seq & 0xff)]
    }
}
