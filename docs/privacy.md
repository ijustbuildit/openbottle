# Privacy and data handling

HydroCap has no account service, backend, analytics SDK, advertising SDK, or vendor-cloud integration. Bottle communication happens locally over Bluetooth. The Android app declares no `INTERNET` permission; the iOS app contains no application networking layer.

## Data in the app

The app stores the selected bottle's identity and preferences, cap measurements, inferred drink events, battery/sync state, and write-reconciliation metadata locally in Room/DataStore (Android) or SwiftData/settings storage (iOS). Device identity is necessary for reconnecting to the same bottle and for stable app-owned Health sync IDs.

Optional body values are used to estimate an editable daily goal. Missing Health data may be supplied manually or left blank. The app is not a medical device, and it does not measure total fluid intake across all food and drinks.

## Optional Health integration

Apple Health: with permission, HydroCap writes dietary-water samples and reads body mass and biological sex for the goal estimate. Apple does not reveal whether an absent read is denied or simply contains no data.

Android Health Connect: with permission, HydroCap writes hydration records and reads available weight records. There is no equivalent biological-sex read in this integration; a manual fallback is optional.

HydroCap updates/deletes only the records it owns, identified by its own sync IDs. Disabling Health sync stops future synchronization; it does not automatically erase previously written Health records. Manage permissions and existing records in the corresponding system Health interface.

Health services follow the operating system's own storage, sharing, backup, cloud-sync, export, and transfer settings. For example, Apple Health can sync through iCloud, and Health Connect supports user-configured exports/transfers. Those are not HydroCap servers. See [Apple's Health security explanation](https://support.apple.com/en-us/108779) and [Health Connect export/import guidance](https://support.google.com/android/answer/15323271?hl=en-GB).

## Backups, diagnostics, and notifications

Android declares `allowBackup=false` and exclusion rules, but device-to-device transfer behavior may also depend on the operating system/OEM. iOS application data and Documents may participate in device/system backups. Do not interpret “local app” as a guarantee that system-managed data can never leave the device.

Debug logs may contain bottle names/serials, BLE addresses, timestamps, sensor values, drink amounts, and synchronization status. Sharing the log or copying it to the clipboard is a user action; inspect/redact it first. No debug log is automatically uploaded by HydroCap.

Local battery/drink notifications can expose status or intake amounts on the lock screen according to the device's notification-preview settings. Drink reminders are off by default. Alerts use the last successfully synchronized information, not continuous live observation.

## Removing data

Uninstalling the app removes its ordinary local application storage according to platform behavior. System backups and previously written Health records are separate; remove them through their respective system controls if desired. Changing/forgetting pairing is not a promise to erase all historical data.

This document describes the implementation, not a blanket regulatory certification or a store privacy declaration. Store disclosures must be checked against the actual release build and distribution configuration.
