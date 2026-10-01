# HydroCap — BRITA LARQ iQ companion app

An independent iOS and Android app for BRITA LARQ iQ smart bottles and compatible LARQ-family caps. Connect over Bluetooth, see battery and bottle-fill estimates, track drinks, configure the LED reminder ring, and optionally sync to Apple Health or Android Health Connect—without a HydroCap, BRITA, or LARQ account.

HydroCap is an unofficial alternative to the BRITA/LARQ bottle app, not a manufacturer-supported app. It is not affiliated with, endorsed by, or supported by BRITA SE or LARQ, Inc. See the [compatibility and limitations](#compatibility-and-limitations) before choosing a bottle profile.

HydroCap does not operate an account service, backend, analytics service, or vendor-cloud integration. Health services, system backups, and user-initiated exports follow the device's own settings; see [Privacy](docs/privacy.md).

## Features

- Home overview: today's recorded intake, an editable daily goal, bottle-fill estimate, and battery level.
- Automatic background sync when the operating system permits it, plus pull-to-refresh. No separate Home sync button.
- History: 1 day, 7 days, 30 days, 90 days, or a rolling year; bars, line, or area; scrolling and value selection.
- Data-driven Auto Y-axis. The hourly day view always scales to its actual recorded amounts, not a full-day goal.
- Daily averages for longer periods, excluding days with no recorded intake. Empty periods remain gaps, not artificial zero-intake days.
- Optional Apple Health / Health Connect hydration writes and weight-based adult goal estimates. Missing inputs may be entered manually or left blank.
- Battery alerts at configurable thresholds, initially 10% and 5%.
- Bottle reminder-ring and quiet-hours controls under Settings.
- Optional local drink reminders, off by default, restricted to verified bottle-ring hours.
- Home / History / Settings navigation, light-blue accent, and System / Light / Dark appearance on both platforms.

## Compatibility and limitations

The implementation has been exercised with a BRITA LARQ iQ cap and a small 680 ml bottle **without a filter**. Other LARQ-family caps, bottle sizes, firmware versions, and filter configurations are not all independently validated. The cap-reported capacity is not used to choose the bottle profile.

The default 680 ml/no-filter volume curve is a measuring-cup calibration fit, not an independently established accuracy guarantee. Fill estimates and inferred drink amounts depend on bottle setup and sensor conditions. See [calibration evidence](docs/protocol/calibration-680-nofilter.md).

The daily goal is an adjustable adult tracking estimate, not medical advice or a prescribed fluid requirement. It does not measure food, other drinks, exercise, climate, or medical circumstances.

Background execution and notification delivery are controlled by iOS/Android. Alerts depend on a successful sync; they are not continuous real-time monitoring. iOS force quit, Bluetooth being off, power restrictions, and device-specific Android restrictions can delay updates.

HydroCap deliberately provides no firmware-update, factory-reset, UV-control, cap-calibration, or unrestricted-command interface.

## Build

| Platform | Requirements | Instructions |
|---|---|---|
| Android | JDK 21; Android SDK with API 36; device Android 10+ | [Android README](android/README.md) |
| iOS | macOS; Xcode with the iOS 26 SDK; iPhone running iOS 26+ | [iOS README](ios/README.md) |

The committed Xcode project can be opened directly. Choose your own local signing team; no developer account or signing key is included. Android uses the checked-in Gradle wrapper. Debug binaries are development builds, not store-signed releases.

## Repository

```text
android/        Native Kotlin / Compose app, Health Connect, JVM and UI tests
ios/            Native SwiftUI app, CoreBluetooth, HealthKit, Swift tests
docs/protocol/  Interoperability specification and sanitized calibration evidence
docs/research/  Public sources, platform differences, verification methodology
docs/legal/     Implementation provenance and release caveats
assets/brand/   Original editable bottle artwork
tools/          Optional developer helpers and cross-platform reference generator
```

Private device captures, implementation briefs, local signing settings, build outputs, and personal test reports are not part of the distributable source tree. Debug logs may contain sensitive device and health information: review and redact them before sharing.

## Development and verification

- Android: `./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug` from `android/`.
- Native Android UI tests: build `:app:assembleDebugAndroidTest`; run on an explicitly selected test device without clearing its data.
- iOS CLI checks on a Mac: `./ios/scripts/typecheck.sh` and `./ios/scripts/test.sh` from the repository root.
- The Catalyst check is **not** a signed iPhoneOS build: SwiftData macro expansion, assets, provisioning, and Xcode-specific diagnostics require Xcode.
- Swift/Kotlin domain parity uses explicitly synthetic fixtures executed against the actual Swift production sources; see [fixture documentation](android/app/src/test/resources/parity/README.md).

See [Contributing](CONTRIBUTING.md), [third-party notices](THIRD_PARTY_NOTICES.md), and the [release checklist](docs/releasing.md).

## License

HydroCap's original code and original artwork are available under [PolyForm Noncommercial 1.0.0](LICENSE). Permitted noncommercial use, modification, and redistribution are governed by that license. Commercial use outside those permissions requires a separate written license from the relevant rights holders; contact the project maintainers through the repository to discuss it.

This is **source-available software**, not an OSI-approved Open Source license. Third-party components retain their own licenses, which are not replaced or restricted by HydroCap's license.

HydroCap is not affiliated with, endorsed by, or supported by BRITA SE or LARQ, Inc. Those names are used only to identify hardware. Hardware trademarks remain the property of their respective owners. Source publication does not imply App Store or Google Play approval.
