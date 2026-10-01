#if os(iOS)
import Foundation
import Testing

@testable import HydroCap

/// Execute against the real app-host bundle, not a synthetic Info.plist fixture.
@Suite("Display branding and update identity")
@MainActor
struct BrandingMetadataTests {
    @Test func newDisplayNamePreservesExistingApplicationIdentity() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["CFBundleDisplayName"] as? String == "OpenBottle")
        #expect(info["CFBundleName"] as? String == "OpenBottle")
        #expect(Bundle.main.bundleIdentifier == "dev.hydrocap.app")
        #expect(info["BGTaskSchedulerPermittedIdentifiers"] as? [String] == ["dev.hydrocap.refresh"])
        let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        #expect(urlTypes.first?["CFBundleURLName"] as? String == "dev.hydrocap.app")
        #expect(urlTypes.first?["CFBundleURLSchemes"] as? [String] == ["hydrocap"])
    }
}
#endif
