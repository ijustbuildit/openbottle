# OpenBottle for Android

Native Kotlin / Jetpack Compose companion app. Package: `dev.hydrocap.app`. Room stores measurements and inferred drinks; DataStore stores preferences; WorkManager performs best-effort background sync; Health Connect is optional. OpenBottle declares no `INTERNET` permission and has no account/backend/vendor-cloud integration.

## Build

Requirements: JDK 21 and Android SDK API 36. Set `JAVA_HOME` to **your** JDK 21 installation. Configure the SDK through `ANDROID_HOME` or an untracked `android/local.properties` containing `sdk.dir=<your-sdk-path>`.

From `android/`:

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
./gradlew :app:assembleDebugAndroidTest
```

The Gradle wrapper and versions in `gradle/libs.versions.toml` are authoritative. `compileSdk` is 36, `targetSdk` is 35, and `minSdk` is 29 (Android 10). Do not silently upgrade the pinned toolchain to silence version-availability warnings.

Development APK: `app/build/outputs/apk/debug/app-debug.apk`. UI test APK: `app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk`.

## Install without deleting existing data

Select the intended test device explicitly. An update must use the same signing certificate as the installed app. Do not uninstall or clear data to bypass a signature mismatch.

```sh
adb -s "$ANDROID_SERIAL" install -r app/build/outputs/apk/debug/app-debug.apk
adb -s "$ANDROID_SERIAL" shell am start -n dev.hydrocap.app/.MainActivity
```

Use the real onboarding permission prompts. Bluetooth is required; Health Connect and notifications may be left off. On Android 10–11, BLE scanning needs the platform's location permission. Android 12+ uses Bluetooth scan/connect permissions; Android 13+ separately requests notification permission.

To run the actual native composable tests after installing the test APK:

```sh
adb -s "$ANDROID_SERIAL" install -r -t app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s "$ANDROID_SERIAL" shell am instrument -w dev.hydrocap.app.test/androidx.test.runner.AndroidJUnitRunner
```

These tests render production components with explicitly synthetic inputs. They do not clear Room, connect to the bottle, or insert synthetic Health records.

## UX and charts

Home / History / Settings match the iOS layout and behavior using Android-native controls. See [UI assets](UI-ASSETS.md) for original artwork and licensed display numerals.

Health-first onboarding begins discovery after the Health choice unless Bluetooth permission already permits a pre-scan. Missing weight and notification access remain optional. Pairing is saved only after notifications and Device Information establish usable GATT readiness. Home opens then; the same app/service-owned job continues importing history without blocking tab navigation. Pre-ready errors stay on Scan; later import errors retain the saved pairing.

Home has equal-height Bottle/Battery cards and no separate sync button. Use pull-to-refresh or best-effort background sync.

History supports 1D / 7D / 30D / 90D / 1Y, bars / line / area, selection, and scrolling for longer ranges. The one-day view shows recorded ml per local hour, including repeated DST hours. Auto Y-axis uses the actual finite plotted peak plus headroom; 1D always uses Auto, including when an older fixed preference is stored. A fixed-to-goal option remains for longer views. A goal above the Auto domain is described in text rather than expanding the scale.

Longer buckets show average ml per day **with positive recorded intake**. Zero/unused days do not lower the average; empty periods are gaps. The whole-range average is weighted by used days, not by averaging month/week means. These display rules do not change raw data or Health writes.

## Health Connect

- Writes `HydrationRecord` entries with stable app-owned `clientRecordId` values and increasing versions. Upserts are deduplicated; unchanged events cause no repeated write.
- Deletes, when algorithm reconciliation requires them, are restricted to IDs OpenBottle itself previously wrote. Other apps' records are never touched.
- Room schema v2 adds the write-tracking table through an automatic migration; there is no destructive migration fallback.
- Optional weight reads use real `WeightRecord` data within the provider's accessible time range. Permission absence and no available sample are distinct states. No synthetic Health value is substituted.
- Health Connect does not expose the equivalent of HealthKit biological sex; this remains an optional manual fallback. See [platform notes](../docs/research/android-health-parity.md).
- The editable adult goal and its caveats are described in the [iOS README](../ios/README.md#daily-drink-goal-an-editable-estimate).

Health Connect can export/transfer data under its own settings. OpenBottle's lack of a backend does not mean Health data can never leave the phone; see [Privacy](../docs/privacy.md).

## BLE, ring controls, and notifications

The cap uses a changing BLE address; saved pairing is based on its advertised name/decoded identity, followed by a fresh scan. The protocol uses Nordic UART, one outstanding request, matching request IDs, bounded reassembly, and an enforced command allowlist.

The only cap-setting writes are clock synchronization, reminder-ring settings, and quiet hours. Reading a cap automatically synchronizes its clock through the existing connection workflow. Ring changes require the user's Apply action and are read back from the cap.

Optional drink notifications default off and require verified, identity-bound ring hours. Native inexact alarms may be delayed; delivery rechecks permission, current settings, time window, and the latest successfully read intake. A query failure is unknown—not fabricated zero intake. Battery alerts use separate configurable thresholds, initially 10% / 5%, and fire when a sync observes a crossing.

Background sync is best effort. WorkManager's periodic interval is not a delivery guarantee, and device power restrictions or a cap out of range may prevent a run. The manual/initial import is owned independently of a screen; duplicate jobs cannot steal its connection.

## Debugging

Settings → Debug exposes the app's own log and read-only diagnostics. Logs can contain device identity, measurements, health amounts, and timestamps. Redact before filing an issue. Debug-only intents exist for scan, sync, live ToF, and reminder reads; some connection paths send the normal clock-setting command, so they are not zero-write hardware probes.

```sh
adb -s "$ANDROID_SERIAL" shell am start -a dev.hydrocap.app.action.DEBUG_SCAN -n dev.hydrocap.app/.MainActivity
adb -s "$ANDROID_SERIAL" shell am start -a dev.hydrocap.app.action.DEBUG_SYNC -n dev.hydrocap.app/.MainActivity
adb -s "$ANDROID_SERIAL" shell am start -a dev.hydrocap.app.action.DEBUG_READ_REMINDER -n dev.hydrocap.app/.MainActivity
```

Do not target other people's caps or stop/uninstall competing apps without their owner's permission. Developer Frida tools are optional, not included in the app, and require explicit device configuration.

## Verification boundaries

JVM tests cover protocol vectors, allowlist, volume state machine, pairing/job ownership, Health record reconciliation, goal/history math, and reminder planning/queue/delivery policy. Cross-platform fixtures run against native Swift-produced results, not a Kotlin-derived oracle. Native UI tests and real-cap/device checks are separate gates; a build or unit-test pass alone proves neither.

OpenBottle's original sources use [PolyForm Noncommercial 1.0.0](../LICENSE). Redistributed dependencies and fonts retain their own licenses; see [Third-party notices](../THIRD_PARTY_NOTICES.md).
