# Executed iOS / Android domain parity fixtures

All inputs are explicitly **synthetic**. They represent no person's drinking, body values, cap measurements, Health records, or actual notification deliveries. Tests never insert them into Room or a real Health store.

Expected outputs are produced by **native execution of the actual Swift production implementations**, not by a separate guessed algorithm or Kotlin-derived oracle. `reference-manifest.json` records the selected reference revision and exact source hashes.

The dynamic-axis revision intentionally supersedes the original frozen reference's goal-inflated Auto scale. Goal resolution, calendar aggregation, zero-day exclusion, and reminder semantics remain unchanged. Regeneration is an explicit reference update for that approved behavior, not an attempt to hide an Android failure.

Cases cover goal provenance/rounding, all five History ranges, multiple calendar/week conventions, spring/fall DST and repeated hours, leap/year/partial-bucket boundaries, used-day weighting, empty/zero periods, exact-now/future admission, and reminder windows/slots/behind rules. Consult the manifest for counts derived from the generated inputs.

`IosReferenceParityTest` compares actual Kotlin production results with every emitted range/bucket/series/summary/scale/goal/slot field using the documented numeric tolerance. This proves domain parity, not BLE readiness, UI rendering, OS delivery, or Health consent.

## Regeneration on a Mac with Swift CLI

1. Confirm the intended behavior revision and source hashes. Do not regenerate merely to make a failing test green. Preserve an unchanged input cohort when comparing before/after behavior.
2. Run `python3 tools/generate-parity-inputs.py` from the repository root.
3. Compile and execute the actual reference sources:

```sh
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  ios/HydroCap/Data/Records.swift \
  ios/HydroCap/Domain/HydrationTarget.swift \
  ios/HydroCap/Domain/HistoryAggregation.swift \
  ios/HydroCap/Domain/ReminderConfig.swift \
  ios/HydroCap/Notify/DrinkReminderPlanner.swift \
  tools/ios-parity-reference.swift -o /tmp/hydrocap-ios-parity-reference
/tmp/hydrocap-ios-parity-reference android/app/src/test/resources/parity
```

4. Run Android's parity tests with JDK 21 and SDK configured:

```sh
cd android
./gradlew :app:testDebugUnitTest --tests dev.hydrocap.app.parity.IosReferenceParityTest
```

The full `:app:testDebugUnitTest` includes these sweeps. No SwiftData/HealthKit/CoreBluetooth substitution or network API participates in reference execution.
