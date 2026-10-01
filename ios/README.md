# HydroCap iOS

SwiftUI port of the Android app: same protocol codec, same ToF algorithm,
same calibrated bottle profile, same command allowlist. No dependencies, no
networking, no account.

## Build & run (Xcode on a Mac with Xcode installed)

1. `cd ios && xcodegen generate` (project is committed, regenerate after
   editing `project.yml`).
2. Open `HydroCap.xcodeproj`, select the `HydroCap` scheme and your iPhone.
   Choose your own local development team in Signing & Capabilities. The
   public project includes no account-specific team. Use a bundle identifier
   registered to that team when needed; the source default is `dev.hydrocap.app`.
3. Run. First launch: Welcome (Connect Apple Health — writes water, reads
   weight + biological sex for the daily target), an "Optional" step only
   when something is missing (Health, notifications, Bluetooth, or weight/sex
   by hand), then "Find your bottle". Scanning starts on Welcome if Bluetooth
   is already allowed; otherwise immediately after the Health choice, before
   the optional/bottle screens. Tap your cap (`LARQ_…`): the card shows only
   Connecting. Once notifications and device information are ready, the app
   saves the verified pairing, opens Home and briefly shows “Bottle connected”.
   Its app-owned job then continues the history import on the same connection;
   navigation is no longer gated on loading the complete log. Connection errors
   stay on Scan; later import errors retain the pairing and appear on Home.
   iOS can still suspend background work; no import timing is guaranteed.
   Requires iOS 26.

## Native Xcode verification

Use full Xcode with the iOS platform installed. An SDK appearing in
`-showsdks` alone does not prove the platform is usable; confirm an eligible
scheme destination. Keep developer selection task-local when another build
workflow still uses Command Line Tools.

From the repository root, with `DEVELOPER_DIR` set to your installed Xcode:

```sh
xcodebuild -project ios/HydroCap.xcodeproj -scheme HydroCap \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project ios/HydroCap.xcodeproj -scheme HydroCap \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -project ios/HydroCap.xcodeproj -scheme HydroCap \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO test
```

The last command requires an installed runtime and a matching simulator.
Simulator tests include the native CoreBluetooth identifier suite; the pure
macOS harness does not substitute a fake framework for it. Test counts should
come from the actual run, including the distinction between test definitions
and parameterized invocations.

The project retains complete concurrency checking. Its CoreBluetooth UUIDs
use on-demand value access, and timeout closures capture value descriptions,
not framework objects. `LM_SKIP_METADATA_EXTRACTION` excludes the unused
AppIntents producer for app/tests because no Shortcuts/AppIntents feature is
defined; it does not filter compiler warnings. Enable that producer if such
a feature is introduced later.

Unsigned device builds do not prove provisioning or HealthKit access.
Real cap interaction, Health authorization and background/notification
behavior still require an iPhone.

## Verification with Command Line Tools

These checks can run on a Mac with the appropriate SDK/frameworks installed,
even when a full Xcode/device toolchain is unavailable. They do not deploy the app.

- `ios/scripts/typecheck.sh` — typechecks the non-macro app layers as Mac
  Catalyst with the project's language settings (0 errors / 0 warnings).
  SwiftData is parsed only: Xcode's macro expansion, asset compilation and
  iPhoneOS diagnostics are not exercised by this check.
- `ios/scripts/test.sh` — compiles the pure-logic sources + tests into a
  macOS Swift Testing binary and runs them. Derive the current test count from
  fresh execution output rather than a fixed documentation total.

Both scripts run from the repo root.

## Design (iOS 26 Liquid Glass)

- Deployment target is **iOS 26.0**: the redesign is built on Liquid Glass
  (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glassProminent)`,
  `tabBarMinimizeBehavior`, `safeAreaBar`), all `@available(iOS 26.0, *)`;
  `if #available` forks would double the UI surface for no user.
- Bottom `TabView`: **Home** (today hero card with the target caption,
  bottle-fill + battery gauges of equal height, today's drinks; no sync
  button — pull-to-refresh and the background sync are the triggers, the
  status line says what is going on), **History** (configurable Swift
  Charts chart, see below, then the grouped drink list), **Settings**
  (native `Form`; Reminder ring & quiet hours, Bottle profile and Debug are
  pushed from there via `model.path`). Onboarding and Scan stay outside the
  tab bar until a cap is paired.
- History chart: range **1 D** / 7 D / 30 D / 90 D / 1 Y (glass segmented), bars /
  line / area and auto / fixed-to-target y axis (glass menu), scrollable x
  axis for 30 D / 90 D / 1 Y (`chartScrollableAxes` + `chartXVisibleDomain`
  + `chartScrollPosition`), tap selection (`chartXSelection`) with a floating
  value label and summary row (average per
  recorded day, best day, days on target). Auto Y-axis uses the actual finite
  plotted peak plus 10% headroom, independent of the daily goal. **1 D** always
  uses Auto, including a previously stored Fixed preference; this does not
  overwrite the longer-range preference. Empty series use a safe 0–100 ml
  display domain. An off-scale daily goal is stated in text, not used to stretch
  Auto; a dashed goal line appears only when it lies inside a non-hourly domain.
  **1 D** shows today's recorded
  water by local calendar hour (ml/hour), including separate repeated DST
  hours; it does not compare hourly intake with a full-day target line.
  The other ranges show **ml/day**, including week/month buckets: first sum
  each local calendar day's drinks,
  then divide by the number of days whose total is >0 ml. Zero/unused days
  do not enter the denominator. The whole-range average is weighted by used
  days, not by month/week count. Empty periods have no average (shown as gaps,
  with disconnected line/area series), not 0 ml/day. Calendar coverage still
  sets the date axis; the selection labels how many days contributed.
  Raw drink events and Health records are not changed. These rules live in
  `Domain/HistoryAggregation` (pure, tested). Controls persist as
  `historyRange` / `historyChartType` / `historyYAxis`.
- Glass rules: glass only for the floating control layer — tab bar, toolbar,
  the primary bottom action (`safeAreaBar` + `.glassProminent`), segmented
  selectors and the interval chips. Content sits on
  `Color(.systemGroupedBackground)` in plain rounded cards
  (`.secondarySystemGroupedBackground`, radius 20, no borders). Never glass
  on content cards.
- Tokens live in `UI/Theme.swift`: accent `#3D9EFA` (applied with `.tint` at
  the root), the water gradient, battery colour tiers (accent / orange /
  red).
- Appearance: Settings → System / Light / Dark, stored as
  `AppSettings.appearance` (`"system"` default) and applied with
  `.preferredColorScheme` at the root (nil = follow iOS).
- Motion: `.contentTransition(.numericText())` on changing numbers,
  `.animation(.snappy, value:)` on state changes, both skipped when Reduce
  Motion is on.

## Daily drink goal (an editable estimate)

The weight reference of 35 ml/kg for adults aged 19–50 includes water from
both food and drinks; it is not a beverage-only requirement.[1]
HydroCap's **explicit product assumption** is a 30% food allowance, so its
starting drink goal is `weight × 35 × 0.70`, rounded to 50 ml within
1.5–4 L. Those bounds are app guardrails, not physiological safe limits.
The sex-only starting goals use the same allowance (male 1.75 L, female
1.50 L after the lower bound); with no usable inputs the adjustable default
is 2 L. There is no additional sex multiplier when weight is known.
This is a rough adult tracking goal, not an individualized medical requirement.
Diet, activity, climate and medical circumstances are not measured. Other
drinks count too; HydroCap's progress only shows this bottle's logged intake.
Prescribed fluid limits take precedence.

Weight (latest `bodyMass` sample) and biological sex are read from Apple
Health after authorization, on launch and when returning from Settings.
Missing Health reads mean **unavailable**, not necessarily permission denied.
Each missing field can be entered manually or left blank. Health values win
per field; a manual target wins when the estimate is switched off. Home,
History and notifications all use the same resolved goal and source caption.
No existing water samples are rewritten by changing this target.

## Drink reminders (local notifications, default off)

Settings → Reminders offers an on/off switch, 1 / 1.5 / 2 / 3-hour frequency
(default 2 hours), and “Only when behind target” (default on). Enabling first
reads the cap's actual ring hours if unknown. Without known valid hours,
there are no notifications: the app must not invent daytime hours that could
conflict with the user's ring settings.

The planner respects midnight and overnight windows in local wall time,
including DST. Each daily slot is compared with the elapsed share of active
hours; tomorrow's first **eligible** slot follows the same rule (no forced
start-of-day nudge). At most eight requests are queued, keyed by fire time.
Planning is based on the last successfully read intake snapshot and the
notification text labels that snapshot; delivery cannot know about drinks
since the last sync. A failed database read is unknown, not zero intake.

Plans are replaced after syncs, settings changes and app launch. The replacement
queue serializes OS writes and invalidates stale plans, so disabling waits
for older adds to settle and removes them. Captured ring hours are refreshed
on sync while reminders are enabled. Scheduling is local; actual iOS prompt,
background execution and notification delivery still need device testing.

## Debug hooks (DEBUG builds)

URL scheme `hydrocap://` — `scan`, `sync`, `tof`, `read-reminder`,
`read-all-settings`; same actions as the Debug screen buttons. Log ring
buffer + `Documents/debug-log.txt`.

## Background sync — what iOS guarantees and what it does not

- A service-filtered background scan (`180A`) runs whenever a cap is paired
  and background sync is on. iOS wakes the app on discovery. The cap rotates
  its address after every disconnect, so without a throttle it would be
  "discovered" again seconds after each sync (observed on device: a sync
  every ~6 s). Background syncs are therefore rate-limited to one per
  15 min after the last successful sync (manual or background); pull-to-refresh
  is never throttled. State restoration is implemented
  (`CBCentralManagerOptionRestoreIdentifierKey`); restored connections are
  cancelled at launch because a connected cap stops advertising.
- `BGAppRefreshTask` `dev.hydrocap.refresh` is a second trigger (earliest
  15 min, 25 s budget). iOS decides when it actually runs; after a force
  quit it never runs until the app is opened again.
- Battery alerts (10 % / 5 %, configurable) are local notifications fired
  from whichever sync observed the level. If iOS does not wake the app for
  hours (Low Power Mode, force quit, Bluetooth off), alerts are delayed —
  this is a platform limit, not a bug.

## Apple Health

Dietary-water samples, 1 s long, metadata `HKMetadataKeySyncIdentifier =
hydrocap:<serial>:<timestamp>` + `HKMetadataKeySyncVersion = event.version`.
From the SDK header (HKMetadata.h): "Saving a HKObject with a
HKMetadataKeySyncIdentifier will replace an existing HKObject with the same
HKMetadataKeySyncIdentifier value if the new HKObject has a greater
HKMetadataKeySyncVersion." So inserts are upserts, no read-before-write.
Deletes only touch samples with our own sync identifiers. The authorization
request shares `dietaryWater` and reads `bodyMass` + `biologicalSex` (see
"Daily water target").

## Only verifiable on a real iPhone

- Bluetooth prompt, scan/connect against the cap, MTU/write length, notify
  delivery, the ~8 s reconnect gap after a disconnect.
- Background wake-ups (scan restoration, BGAppRefreshTask cadence).
- HealthKit authorization sheet, the samples appearing in Health, and the
  weight/sex read (whether Health has a weight, whether reading is allowed).
- Notification delivery: battery alerts and the drink reminders (pending
  requests are visible only on device; the Debug log lists every re-plan).
- All UI on device (layout, pickers, navigation, chart scrolling and tap
  selection) — the Catalyst typecheck proves it compiles, not how it looks.

## Privacy and licensing

Health and system backups/exports follow the operating system's own settings;
no HydroCap account/backend is involved. Debug logs are sensitive and should
be redacted before sharing. See [Privacy](../docs/privacy.md).

Original sources and independently authored bottle artwork use
[PolyForm Noncommercial 1.0.0](../LICENSE). Apple system symbols inside the
native iOS UI remain system-provided assets, not redistributed app branding.

## Sources

[1] https://www.dge.de/wissenschaft/referenzwerte/wasser — DGE – Referenzwerte Wasser
