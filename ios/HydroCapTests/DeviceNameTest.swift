import Foundation
import Testing

@testable import HydroCap

// Synthetic IDs: integers 0x0123456789ABCDEF and 0xFEDCBA9876543210,
// encoded with alphabet 0-9A-Za-z and left-padded to 11 base62 digits.
@Suite("Device name")
struct DeviceNameTest {

    @Test func decodesSyntheticLeadingZeroExample() {
        #expect(DeviceName.decodeDeviceId("LARQ_063UfDVRKBz") == "0123456789ABCDEF")
    }

    @Test func decodesSyntheticUnsignedUpperHalfSerialNumber() {
        #expect(DeviceName.decodeDeviceId("LARQ_LscmunaixMG") == "FEDCBA9876543210")
    }

    @Test func rejectsNamesOfAnotherShape() {
        #expect(DeviceName.decodeDeviceId(nil) == nil)
        #expect(DeviceName.decodeDeviceId("CapDFU") == nil)
        #expect(DeviceName.decodeDeviceId("LARQ_short") == nil)
        #expect(DeviceName.decodeDeviceId("LARQ_063UfDVRKB!") == nil)
        // 11 characters but a non-base62 symbol in the middle.
        #expect(DeviceName.decodeDeviceId("LARQ_063UfD-RKBz") == nil)
    }

    @Test func matcherIsACaseInsensitiveContains() {
        #expect(DeviceName.matches("LARQ_LscmunaixMG"))
        #expect(DeviceName.matches("my larq cap"))
        #expect(!DeviceName.matches("CapDFU"))
        #expect(!DeviceName.matches(nil))
    }
}

// Uses the generated synthetic IDs above and a locally administered test address.
@Suite("Cap advertisement matcher")
struct CapAdvertisementMatcherTest {

    @Test func matchesSyntheticAdvertisementByNameAndManufacturerData() {
        #expect(CapAdvertisementMatcher.matchesName("LARQ_LscmunaixMG"))
        // AD 0xff payload after the company id 0x0059: "CAP"
        #expect(CapAdvertisementMatcher.matchesManufacturerData(Data([0x43, 0x41, 0x50])))
        #expect(CapAdvertisementMatcher.matchesManufacturerData(Data("CAP123".utf8)))
        #expect(!CapAdvertisementMatcher.matchesManufacturerData(Data([0x43, 0x41])))
        #expect(!CapAdvertisementMatcher.matchesManufacturerData(nil))
        #expect(!CapAdvertisementMatcher.matchesManufacturerData(Data("DFU".utf8)))
    }

    @Test func pairedCapIsRecognisedByIdOrNameNeverByAddress() {
        let cap = DiscoveredCap(
            name: "LARQ_LscmunaixMG",
            address: "02:00:00:00:00:01",
            rssi: -66,
            deviceIdHex: "FEDCBA9876543210",
            rawAdvertisementHex: nil,
            matchedByName: true,
            matchedByManufacturerData: true,
            seenAtMs: 0,
        )
        #expect(cap.isSameCap(pairedName: "LARQ_LscmunaixMG", pairedDeviceIdHex: nil))
        #expect(cap.isSameCap(pairedName: nil, pairedDeviceIdHex: "fedcba9876543210"))
        #expect(!cap.isSameCap(pairedName: "LARQ_063UfDVRKBz", pairedDeviceIdHex: "0123456789ABCDEF"))
        #expect(!cap.isSameCap(pairedName: nil, pairedDeviceIdHex: nil))
        // The rotating private address must not be part of the identity.
        #expect(!cap.isSameCap(pairedName: "02:00:00:00:00:01", pairedDeviceIdHex: nil))
    }
}

@Suite("Request id counter")
struct RequestIdCounterTest {

    @Test func startsAtOneAndIncreases() {
        let counter = RequestIdCounter()
        #expect(counter.next() == 1)
        #expect(counter.next() == 2)
        #expect(counter.next() == 3)
        #expect(counter.current == 3)
    }

    @Test func wrapsAroundFixed32SkippingZero() {
        let counter = RequestIdCounter(start: 0xFFFF_FFFE)
        #expect(counter.next() == 0xFFFF_FFFF)
        #expect(counter.next() == 1)
    }
}
