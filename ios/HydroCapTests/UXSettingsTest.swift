import Foundation
import Testing
@testable import HydroCap

@Suite("UX settings persistence")
@MainActor
struct UXSettingsTest {
    func withStore(_ body: (SettingsStore) -> Void) {
        let name = "dev.hydrocap.ux-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(SettingsStore(defaults: defaults))
    }
    @Test func remindersStartOffAndAppearanceFollowsSystem() {
        withStore {
            #expect(!$0.current.drinkRemindersEnabled)
            #expect($0.current.appearance == "system")
            #expect($0.current.ringWindow == nil)
        }
    }
    @Test func missingManualFieldsRemainOptional() {
        withStore {
            $0.setManualBody(weightKg: nil, sex: .female)
            #expect($0.current.manualWeightKg == nil)
            #expect($0.current.manualSex == "female")
            $0.setManualBody(weightKg: 70, sex: nil)
            #expect($0.current.manualWeightKg == 70)
            #expect($0.current.manualSex == nil)
            $0.setManualBody(weightKg: nil, sex: nil)
            #expect($0.current.manualWeightKg == nil)
            #expect($0.current.manualSex == nil)
        }
    }
    @Test func capturedHoursBelongToTheSelectedBottle() {
        withStore {
            $0.setPairedDevice(name: "fixture-a", deviceIdHex: "AAAAAAAAAAAAAAAA")
            $0.setLastRingHours(startSec: 28_800, stopSec: 78_300)
            $0.setDrinkReminders(enabled: true, frequencyMinutes: 120, onlyWhenBehind: true)
            $0.setPairedDevice(name: "fixture-a", deviceIdHex: "AAAAAAAAAAAAAAAA")
            #expect($0.current.ringWindow != nil)
            #expect($0.current.drinkRemindersEnabled)
            $0.setPairedDevice(name: "fixture-b", deviceIdHex: "BBBBBBBBBBBBBBBB")
            #expect($0.current.ringWindow == nil)
            #expect(!$0.current.drinkRemindersEnabled)
        }
    }
    @Test func forgettingDisablesBottleBasedReminders() {
        withStore {
            $0.setPairedDevice(name: "fixture-a", deviceIdHex: "AAAAAAAAAAAAAAAA")
            $0.setLastRingHours(startSec: 28_800, stopSec: 78_300)
            $0.setDrinkReminders(enabled: true, frequencyMinutes: 90, onlyWhenBehind: true)
            $0.forgetDevice()
            #expect(!$0.current.hasPairedDevice)
            #expect(!$0.current.drinkRemindersEnabled)
            #expect($0.current.ringWindow == nil)
        }
    }
    @Test func chartControlsAndManualTargetRoundtrip() {
        withStore {
            $0.setHistoryControls(range: "90d", chartType: "area", yAxis: "fixed")
            $0.setDailyTarget(useEstimate: false, overrideMl: 2_530)
            #expect($0.current.historyRange == "90d")
            #expect($0.current.historyChartType == "area")
            #expect($0.current.historyYAxis == "fixed")
            #expect(!$0.current.dailyTargetUseEstimate)
            #expect($0.current.dailyTargetOverrideMl == 2_550)
        }
    }
}
