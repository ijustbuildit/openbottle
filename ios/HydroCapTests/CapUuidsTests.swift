#if os(iOS)
import CoreBluetooth
import Testing

@testable import HydroCap

/// Native framework regressions; the macOS pure-logic harness excludes this
/// iOS-only suite rather than replacing CoreBluetooth with a fake type.
@Suite("GATT identifier values")
@MainActor
struct CapUuidsTests {
    @Test func identifiersKeepTheirPublishedWireValues() {
        let identifiers: [(CBUUID, String)] = [
            (CapUuids.deviceInformationService, "180A"),
            (CapUuids.manufacturerName, "2A29"),
            (CapUuids.modelNumber, "2A24"),
            (CapUuids.serialNumber, "2A25"),
            (CapUuids.firmwareRevision, "2A26"),
            (CapUuids.hardwareRevision, "2A27"),
            (CapUuids.softwareRevision, "2A28"),
            (CapUuids.batteryService, "180F"),
            (CapUuids.batteryLevel, "2A19"),
            (CapUuids.nusService, "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
            (CapUuids.nusRx, "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"),
            (CapUuids.nusTx, "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"),
            (CapUuids.dfuService, "FE59"),
        ]
        for (identifier, expected) in identifiers {
            #expect(identifier == CBUUID(string: expected))
        }
        #expect(CapUuids.scanServices == [CBUUID(string: "180A")])
    }

    @Test func repeatedLookupsKeepValueEqualityAndNames() {
        let first = CapUuids.nusRx
        let second = CapUuids.nusRx
        #expect(first == second)
        #expect(CapUuids.shortName(first) == "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    }
}
#endif
