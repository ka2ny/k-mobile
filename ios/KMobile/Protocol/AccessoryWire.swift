import Foundation

enum AccessoryFailure: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

/// Limited protobuf wire codec for the published ESP-IDF provisioning messages.
/// Bounded input, no recursion, strict types and duplicate singular fields rejected.
struct Proto {
    enum Value { case number(UInt64), bytes(Data) }
    private var fields: [Int: [Value]] = [:]
    init(_ data: Data) throws {
        guard data.count <= 16_384 else { throw AccessoryFailure.invalid("Setup response is too large.") }
        let bytes = Array(data)
        var offset = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for index in 0..<10 {
                guard offset < bytes.count else { throw AccessoryFailure.invalid("Incomplete setup response.") }
                let byte = bytes[offset]; offset += 1
                guard index != 9 || byte <= 1 else { throw AccessoryFailure.invalid("Invalid setup integer.") }
                result |= UInt64(byte & 127) << (index * 7)
                if byte & 128 == 0 { return result }
            }
            throw AccessoryFailure.invalid("Invalid setup integer.")
        }
        while offset < bytes.count {
            let key = try varint()
            let field = Int(key >> 3)
            guard field > 0, field <= 536_870_911 else { throw AccessoryFailure.invalid("Invalid setup field.") }
            switch key & 7 {
            case 0: fields[field, default: []].append(.number(try varint()))
            case 2:
                let count = try varint()
                guard count <= UInt64(bytes.count - offset) else { throw AccessoryFailure.invalid("Incomplete setup field.") }
                fields[field, default: []].append(.bytes(Data(bytes[offset..<(offset + Int(count))])))
                offset += Int(count)
            default: throw AccessoryFailure.invalid("Unsupported setup field type.")
            }
        }
    }
    func number(_ field: Int) throws -> UInt64 {
        guard let values = fields[field] else { return 0 }
        guard values.count == 1, case .number(let value) = values[0] else { throw AccessoryFailure.invalid("Invalid setup field type.") }
        return value
    }
    func bytes(_ field: Int) throws -> Data {
        guard let values = fields[field], values.count == 1, case .bytes(let value) = values[0] else {
            throw AccessoryFailure.invalid("Missing or invalid setup field.")
        }
        return value
    }
    func repeated(_ field: Int) throws -> [Data] {
        try (fields[field] ?? []).map { value in
            guard case .bytes(let data) = value else { throw AccessoryFailure.invalid("Invalid setup list.") }
            return data
        }
    }
    static func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes: [UInt8] = []
        repeat { bytes.append(UInt8(value & 127) | (value > 127 ? 128 : 0)); value >>= 7 } while value != 0
        return Data(bytes)
    }
    static func number(_ field: Int, _ value: UInt64) -> Data { varint(UInt64(field << 3)) + varint(value) }
    static func bytes(_ field: Int, _ value: Data) -> Data { varint(UInt64(field << 3 | 2)) + varint(UInt64(value.count)) + value }
    static func message(_ type: UInt64, _ field: Int, _ payload: Data = Data()) -> Data {
        number(1, type) + bytes(field, payload)
    }
}

struct RelayFrame: Equatable {
    enum Kind: UInt8 { case open = 1, opened, data, close, credit, hint }
    let kind: Kind
    let stream: UInt8
    let payload: Data
    init(kind: Kind, stream: UInt8, payload: Data = Data()) {
        self.kind = kind; self.stream = stream; self.payload = payload
    }
    init(_ data: Data, maximum: Int = 253) throws {
        let bytes = Array(data)
        guard bytes.count >= 2, bytes.count <= maximum, let kind = Kind(rawValue: bytes[0]) else {
            throw AccessoryFailure.invalid("Unsupported Bluetooth frame.")
        }
        self.init(kind: kind, stream: bytes[1], payload: Data(bytes.dropFirst(2)))
        switch kind {
        case .close: guard payload.isEmpty else { throw AccessoryFailure.invalid("Invalid close frame.") }; break
        case .opened: guard payload.count == 1 else { throw AccessoryFailure.invalid("Invalid open result.") }; break
        case .credit: guard payload.count == 2 else { throw AccessoryFailure.invalid("Invalid credit frame.") }; break
        case .hint: guard stream == 0, payload.count <= 32 else { throw AccessoryFailure.invalid("Invalid network hint.") }; break
        case .open, .data: guard !payload.isEmpty else { throw AccessoryFailure.invalid("Empty Bluetooth frame.") }; break
        }
    }
    var encoded: Data { Data([kind.rawValue, stream]) + payload }
    var credit: Int { payload.count == 2 ? Int(payload[payload.startIndex]) + (Int(payload[payload.startIndex + 1]) << 8) : 0 }
}

struct RelayTarget: Equatable {
    let host: String
    let port: UInt16
    static func parse(_ payload: Data) throws -> [Self] {
        guard let text = String(data: payload, encoding: .utf8), !text.isEmpty else { throw AccessoryFailure.invalid("Invalid relay destination.") }
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { throw AccessoryFailure.invalid("Too many relay destinations.") }
        return try parts.map { part in
            // Contract v0 supplies IPv4 literals only; never turn an opaque frame into DNS or a URL.
            let address = part.split(separator: ":", omittingEmptySubsequences: false)
            guard address.count == 2, let port = UInt16(address[1]), port != 0 else { throw AccessoryFailure.invalid("Invalid relay address.") }
            let octets = address[0].split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4, octets.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) && UInt8($0) != nil }),
                  let first = UInt8(octets[0]), first > 0, first < 224, first != 127,
                  address[0] != "169.254.169.254" else { throw AccessoryFailure.invalid("Unsupported relay address.") }
            return Self(host: String(address[0]), port: port)
        }
    }
}

struct RelayWindow {
    static let capacity = 8192
    private(set) var available = capacity
    mutating func consume(_ count: Int) throws {
        guard count >= 0, count <= available else { throw AccessoryFailure.invalid("Relay window exceeded.") }
        available -= count
    }
    mutating func grant(_ count: Int) throws {
        guard count > 0, count <= Self.capacity - available else { throw AccessoryFailure.invalid("Invalid relay credit.") }
        available += count
    }
}
