# Android / iOS verification methodology

Both native clients share the same functional contract, but not platform permission sheets, rendering engines, or operating-system scheduling guarantees.

## Distinct verification layers

| Layer | Evidence | Does not prove |
|---|---|---|
| Swift pure logic | Production sources compiled into the Swift Testing executable | iPhone signing, SwiftData macro expansion, UI or BLE behavior |
| Swift Catalyst check | Non-macro app sources checked with project language flags; persistence parsed separately | Signed iPhoneOS build, asset compilation, Xcode-only diagnostics |
| Kotlin JVM | Production domain/protocol/job/Health/reminder logic exercised by unit tests | Native permission sheets, GATT interaction, OS alarm delivery |
| Cross-language fixtures | Native Swift production execution compared against actual Kotlin production objects | Device data, platform UI, live notification or Health behavior |
| Native Compose tests | Production composables with labelled synthetic fixtures on a test device | Slow real log import, hardware interaction, real Health data |
| Real-device acceptance | Actual installed app, preserved data, real cap readiness/sync, system Health permissions | Universal hardware/firmware compatibility or guaranteed scheduling |

Test counts change as coverage evolves. Record counts, failures, toolchain limits, source identity, and build outputs from the actual run rather than keeping a stale count in the README.

## Chart parity

Today is a local-calendar-day hourly view. DST repeated hours remain distinct. Longer periods show daily averages weighted by days with positive recorded intake; unused/zero days are excluded, and empty periods are gaps. Selected ranges use exact calendar boundaries, with partial first/current buckets.

Auto Y-axis derives from the actual plotted data, not the daily goal. Hourly detail always uses Auto, including a legacy fixed preference. Non-hourly explicit Fixed remains a user choice. Off-scale goal information does not stretch Auto.

## Reproduction

- Follow [Android build/test instructions](../../android/README.md).
- Follow [iOS verification/build instructions](../../ios/README.md).
- Regenerate cross-language fixtures through the [native Swift reference procedure](../../android/app/src/test/resources/parity/README.md), only after explicitly selecting the intended source revision/hashes.
- Update-install Android with the matching signer. Do not uninstall, clear Room, insert synthetic Health data, or overwrite an owner's preferences to obtain a passing test.
- Exercise background sync and notification delivery separately; local scheduler/unit-test success is not evidence of a delivered notification.

Private hardware logs, real intake screenshots, device serials, local paths, account/team IDs, signing fingerprints, and operator diaries are intentionally excluded from this public methodology.
