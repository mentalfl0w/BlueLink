import Foundation

/// Stable identity of a classic Bluetooth device.
///
/// The canonical form is the six-octet address in upper-case hexadecimal with
/// hyphen separators (`AA-BB-CC-DD-EE-FF`), matching `IOBluetoothDevice.addressString`.
/// Names are presentation data and never participate in identity.
public struct DeviceID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let address: String

    public init?(raw: String) {
        let hex = raw.uppercased().filter { $0.isHexDigit }
        guard hex.count == 12, hex.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            return nil
        }
        var octets: [Substring] = []
        octets.reserveCapacity(6)
        var index = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(index, offsetBy: 2)
            octets.append(hex[index..<next])
            index = next
        }
        address = octets.joined(separator: "-")
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = DeviceID(raw: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid Bluetooth address")
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(address)
    }

    public var description: String { address }

    public static func < (lhs: DeviceID, rhs: DeviceID) -> Bool {
        lhs.address < rhs.address
    }
}
