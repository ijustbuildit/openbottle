import CoreBluetooth
import Foundation

/// GATT identifiers from docs/protocol/ble-protocol.md §2. `nonisolated`
/// because the CoreBluetooth delegate queue logs with them. Each accessor
/// creates a framework value on demand: the app retains no global
/// non-Sendable CBUUID reference across executor boundaries.
nonisolated enum CapUuids {
    static var deviceInformationService: CBUUID { CBUUID(string: "0000180a-0000-1000-8000-00805f9b34fb") }
    static var manufacturerName: CBUUID { CBUUID(string: "00002a29-0000-1000-8000-00805f9b34fb") }
    static var modelNumber: CBUUID { CBUUID(string: "00002a24-0000-1000-8000-00805f9b34fb") }
    static var serialNumber: CBUUID { CBUUID(string: "00002a25-0000-1000-8000-00805f9b34fb") }
    static var firmwareRevision: CBUUID { CBUUID(string: "00002a26-0000-1000-8000-00805f9b34fb") }
    static var hardwareRevision: CBUUID { CBUUID(string: "00002a27-0000-1000-8000-00805f9b34fb") }
    static var softwareRevision: CBUUID { CBUUID(string: "00002a28-0000-1000-8000-00805f9b34fb") }

    static var batteryService: CBUUID { CBUUID(string: "0000180f-0000-1000-8000-00805f9b34fb") }
    static var batteryLevel: CBUUID { CBUUID(string: "00002a19-0000-1000-8000-00805f9b34fb") }

    static var nusService: CBUUID { CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e") }
    /// Phone → cap (write).
    static var nusRx: CBUUID { CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e") }
    /// Cap → phone (notify).
    static var nusTx: CBUUID { CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e") }

    /// Secure DFU service: listed only so the code and the tests can assert it
    /// is never touched.
    static var dfuService: CBUUID { CBUUID(string: "0000fe59-0000-1000-8000-00805f9b34fb") }

    /// Services the scan filters on. `0x180A` is in the primary advertisement
    /// (hardware session 1); the manufacturer data sits in the scan response
    /// and is not usable as a scan filter on iOS.
    static var scanServices: [CBUUID] { [deviceInformationService] }

    static func shortName(_ uuid: CBUUID) -> String {
        let value = uuid.uuidString.uppercased()
        return value.hasSuffix("-0000-1000-8000-00805F9B34FB") ? "0x" + value.prefix(4) : value
    }
}
