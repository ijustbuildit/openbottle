import Foundation

/// One advertising cap as shown in the scan list.
nonisolated struct DiscoveredCap: Sendable, Equatable, Identifiable {
    var name: String?
    /// The CoreBluetooth identifier (a UUID string). It is *not* stable across
    /// connections: the cap rotates its resolvable private address, so a
    /// changed identifier is normal and every connect needs a fresh scan.
    var address: String
    var rssi: Int
    var deviceIdHex: String?
    var rawAdvertisementHex: String?
    var matchedByName: Bool
    var matchedByManufacturerData: Bool
    var seenAtMs: Int64

    var id: String { address }

    var displayName: String { name ?? "(no name)" }

    /// Whether this result is the paired cap (matched by name or decoded
    /// serial, never by address).
    func isSameCap(pairedName: String?, pairedDeviceIdHex: String?) -> Bool {
        if let pairedDeviceIdHex, let deviceIdHex, deviceIdHex.caseInsensitiveCompare(pairedDeviceIdHex) == .orderedSame {
            return true
        }
        if let pairedName, let name, name == pairedName {
            return true
        }
        return false
    }
}

/// Pure matching logic shared by the CoreBluetooth scanner and unit tests.
nonisolated enum CapAdvertisementMatcher {
    static let manufacturerIdNordic: UInt16 = 0x0059
    static let manufacturerPrefixCap: [UInt8] = Array("CAP".utf8)

    static func matchesName(_ name: String?) -> Bool { DeviceName.matches(name) }

    static func matchesManufacturerData(_ manufacturerData: Data?) -> Bool {
        guard let manufacturerData, manufacturerData.count >= manufacturerPrefixCap.count else { return false }
        return manufacturerData.prefix(manufacturerPrefixCap.count).elementsEqual(manufacturerPrefixCap)
    }
}
