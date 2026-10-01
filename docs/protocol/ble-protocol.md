# LARQ / BRITA LARQ iQ cap — BLE protocol (clean-room spec)

This specification originated from interface analysis and community evidence.
Hardware confirmations and corrections are recorded separately in
`hw-session-1.md`; those observations apply to the tested configuration.
Claims below retain their original evidence tags:

- `[APP]`  — observed in the decompiled BRITA Android app 1.1.0 (com.brita.britaapp,
  APK sha256 `72fc368d734f52d1da31234f7fa9f1f8b8825e016c1ac00656e24704bb6b4cc1`).
  The APK ships `cap_ble.proto` (header `// v1.13`) as a plain asset.
- `[LARQ-APP]` — from the decompiled *LARQ* app as reported by community
  projects (albi005/bottle research.md, rossvz/larq-tui docs). Same protocol
  family; the BRITA app is a rebrand of the LARQ app stack (`com.product.*`
  packages, `LARQ_` name prefix, "larq" scan matcher).
- `[COMMUNITY]` — physical observation reported by third parties on original
  LARQ PureVis 2 bottles, not yet reproduced by us.
- `[HYPOTHESIS]` — our inference; must be confirmed on hardware.

This file is written from scratch. No vendor source code is copied; the
vendor `.proto` itself is **not** vendored into this repo (see
`docs/legal/notes.md`). Our own schema lives in
`android/app/src/main/proto/hydrocap.proto` and must stay wire-compatible
with the tables below.

## 1. Discovery

| Item | Value | Evidence |
|---|---|---|
| Advertised service (scan filter) | Device Information `0x180A` | `[APP]` `CoreBleScanner` filters by `0000180A-…` |
| Name prefix | `LARQ_` + 11 base62 chars | `[APP]` `DeviceNameAlgoKt` (`PERIPHERAL_NAME_DEVICE_ID = 11`), scan matcher `"larq"` (case-insensitive contains) |
| Name → device id | base62-decode the 11-char suffix into a 16-hex-digit id, upper-case, zero-padded to 16 | `[APP]` `Base62`: alphabet `0-9A-Za-z`, big-endian |
| Manufacturer data | company id `0x0059` (Nordic), payload starts with ASCII `CAP` | `[COMMUNITY]` albi005 scan filter; not in BRITA app |
| DFU-mode name | `CapDFU` (bottle), `LarqDFU` (pitcher) | `[APP]` `BleConstants.DFUNames` |
| Sleep | cap stops advertising after ~15 s idle; tap/tilt wakes it | `[COMMUNITY]` rossvz |

The decoded value is also readable from Serial Number String `0x2A25`.
Public conversion tests use explicitly generated synthetic device identities,
not an owner's observed name or serial.

## 2. GATT layout

| Service | Characteristic | UUID | Use | Evidence |
|---|---|---|---|---|
| Device Information `0x180A` | Model `2A24`, Serial `2A25`, FW `2A26`, HW `2A27`, SW `2A28` | standard | identity | `[APP]` |
| Battery `0x180F` | Battery Level `2A19` | standard | read + notify, 0–100 % | `[APP]` `bindBattery` |
| Nordic UART Service | service `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | | request/response channel | `[APP]` |
| | RX (phone → cap) `6e400002-…` | write | protobuf `CapBleRequest` | `[APP]` `WRITE_CHARACTERISTIC` |
| | TX (cap → phone) `6e400003-…` | notify | protobuf `CapBleResponse` | `[APP]` `READ_CHARACTERISTIC` |
| Secure DFU `0xFE59` | Buttonless DFU w/o bonds `8ec90003-f315-4f60-9fb8-838830daea50` | **never touched by us** | `[APP]` |

Write type: the BRITA app writes NUS RX with the library default
`WRITE_TYPE_DEFAULT` (= with response) `[APP]` (`CoreBtCharacteristic.write`
→ `Ki.i.DEFAULT` = Android write type 2). albi005 uses
`WRITE_TYPE_NO_RESPONSE` `[COMMUNITY]`. Start with *with response*; fall
back if the cap rejects it.

MTU: the BRITA app never calls `requestMtu` `[APP]`. Max message size is
documented as 182 bytes in the vendor schema comment `[APP]`, which exceeds
the 20-byte default ATT payload → the cap must negotiate a larger MTU itself
or rely on the phone's default (Android typically negotiates 517 on
connect since API 26 for some stacks — `[HYPOTHESIS]`, verify by logging the
first notification length). If notifications arrive fragmented at 20 bytes,
reassembly is our job (`[HYPOTHESIS]`; the app parses each notification as a
whole `CapBleResponse`, which only works if the stack delivers complete
values).

Bonding/encryption: none. No `createBond`, no LE Secure Connections, no
application-level auth in the BRITA app `[APP]`; community confirms "zero
authentication" `[COMMUNITY]`. Ownership is enforced only server-side by the
BRITA cloud (`ProductOwnershipService.ownership(deviceId)`), which we don't
use.

Concurrency: one outstanding request at a time. `[COMMUNITY]` rossvz reports
lost responses with parallel requests; the BRITA app also serialises
commands with a retry strategy `[APP]` (`BottleCommandRetryStrategy`,
`BottleConfig.timeoutInterval/retryCount` from remote config).

## 3. Envelope

proto3, no length prefix, no framing `[APP]`/`[LARQ-APP]`:

```
CapBleRequest  { fixed32 requestId = 1; google.protobuf.Any body = 2; }
CapBleResponse { fixed32 requestId = 1; CapEnumResponseCode code = 2; google.protobuf.Any body = 3; }
CapEnumResponseCode { FAIL = 0; SUCCESS = 1; NOT_SUPPORTED = 2; }
```

`Any.type_url` is `type.googleapis.com/<MessageName>` with the **unqualified**
message name (the vendor schema has no `package` statement) `[APP]`. The
request id is an app-side counter; responses echo it. Setters answer with
`SUCCESS` and an empty/absent body `[APP]`.

Timestamps in log records are Unix seconds `[APP]` (schema comment
"timestamp - unix epoch in sec"). `RequestSetCapTimeSettings` carries
**milliseconds** (`timeInMillisec`) `[APP]`; the BRITA app sends
`Instant.now().toEpochMilli()` right after connecting, before anything else
`[APP]` (`BottleCommunicationDevice.setup` → `setTime()`).

## 4. Messages we use (MVP)

| Command | Request body | Response body | Notes / evidence |
|---|---|---|---|
| set time | `RequestSetCapTimeSettings{ settings{ uint64 timeInMillisec=1 } }` | none | first command after connect `[APP]` |
| ui state | `RequestGetCapUiState{}` | `ResponseGetCapUiState{ CapEnumUiState state=1; CapPowerSavingMode powerSavingMode=2 }` | states 0..18, e.g. 7=BATTERY_LOW, 8=CHARGING, 9=CHARGED `[APP]` |
| ToF settings | `RequestGetCapTofSettings{}` | `ResponseGetCapTofSettings{ settings{ mode=1(enum); bool isIntervalTriggerEnabled=2; fixed32 triggerIntervalInSec=3; fixed32 accelerometerCheckIntervalInSec=4; fixed32 bottleSizeInMilliliter=5; fixed32 accelerometerTimeoutInSec=6 } }` | Capacity is informational: the tested physical 680 ml bottle reported 1000 ml. Never auto-select a profile from this field; see hardware notes. |
| ToF log | `RequestGetCapTofLog{ query{ uint64 fromTimestamp=1; fixed32 limit=2; CapEnumLogQuerySearchAlgo algo=3 } }` | `ResponseGetCapTofLog{ repeated CapTofLog items=1 }` with `CapTofLog{ uint64 timestamp=1; CapEnumTofTriggerType triggerType=2; fixed32 distanceInMillimeter=3; fixed32 kcps=4; float uvLedTempInOhm=5 }` | returns first `limit` entries with `timestamp > fromTimestamp` ascending `[APP]` (schema comment: "non-inclusive"). BRITA default `limit=5` for readTofLog `[APP]` (remote-config default `("readTofLog", 5, 4, 0)`), retries fall back to `SEARCH_ALGO_TIMESTAMP`. albi005 uses limit 6 and stops when `items.size < limit`. |
| ToF state (live) | `RequestGetCapTofState{}` | `ResponseGetCapTofState{ state{ fixed32 distanceInMillimeter=1; fixed32 kcps=2 } }` | on-demand measurement; also creates a `TYPE_REQUEST` log entry `[APP]` (enum comment) |
| activation log | `RequestGetCapActivationLog{ query }` | `ResponseGetCapActivationLog{ repeated CapActivationLog items }`, `CapActivationLog{ uint64 timestamp=1; CapEnumUvActivationMode mode=2; fixed32 batterySocInPercentage=3 }` | historical battery SoC per UV cycle — nice for a battery history chart |
| hydro reminder | `RequestGet/SetCapHydroReminderSettings{ settings{ state=1(enum OFF/INTERVAL_FIXED/INTERVAL_ADAPTIVE); fixed32 startTimeInSec=2; fixed32 stopTimeInSec=3; fixed32 intervalInSec=4; CapColor color=5 } }`, `CapColor{ float red,green,blue,alpha = 1..4 (0..1) }` | | the only user-facing LED control. `start/stop` are seconds-of-day 1..86400 `[APP]`. |
| do-not-disturb | `RequestGet/SetCapDoNotDisturbSettings{ settings{ state=1 (OFF/ON/AUTO); fixed32 startTimeInSec=2; stopTimeInSec=3; snoozeTimeInMinutes=4 } }` | | quiet hours for the ring |
| low-battery settings | `RequestGetCapLowBatterySettings{}` | `ResponseGetCapLowBatterySettings{ settings{ fixed32 alertThresholdInPercentage=1; fixed32 lockoutThresholdInPercentage=2 } }` | read-only for us (informational) |

Commands that exist but are **out of scope and must not be sent**:
`RequestSetCapUvActivate`, `RequestSet*Config/Threshold/AdcProtection/
LowBatterySettings/TofSettings/CalibrationSettings`,
`RequestCapStart/StopCapCalibration`, `RequestCapEnterLowBatteryMode`,
`RequestCapEnterDfuMode`, `RequestCapFactoryReset`,
`RequestSetCapPowerSavingMode`, `RequestSetCapBottleSensorState`.
(Full inventory: 39 command keys `[APP]` `CommandKey`.)

## 5. ToF → volume (hydration algorithm)

The cap stores raw ToF distances (mm from the cap to the water surface).
Volume conversion happens in software.

- BRITA app: does **not** contain a conversion `[APP]` — it uploads
  `cap_tof_event_logs` to the cloud (`EventLogsRepositoryImpl`, Azure
  Europe-West per BRITA's Data Act page) and receives hydration data back.
  Volume math therefore lives server-side (`[HYPOTHESIS]`, consistent with
  reviews saying tracking needs internet).
- LARQ app 1.6.1 `[LARQ-APP]` (per albi005's clean-room notes): 4th-degree
  polynomial `V(d) = c0·d⁴ + c1·d³ + c2·d² + c3·d + c4`, clamped at
  `minVolume`, with `tofMax = 250 mm` (readings ≥ tofMax are "sensor could
  not read"), `drinkThreshold = 15 ml`, `fillThreshold = 100 ml`.
  Reported coefficients: 1000 ml body `(-1.1e-6, 5.5211e-4, -0.08516349,
  -0.2839113, 1026.71212239)`; 680 ml body `(-1.19e-6, 5.0264e-4,
  -0.06522747, -0.81937241, 715.15212206)`.
  Sanity (our evaluation of the reported polynomials): 680 ml body → 715 ml
  at d=0, ≈619 ml at 37 mm, ≈59 ml at 200 mm, crosses 0 at ≈215 mm;
  1000 ml body → 1027 ml at d=0, ≈926 ml at 37 mm, ≈55 ml at 237 mm.
  That matches rossvz's "full ≈37 mm / empty ≈237 mm" for the 34 oz (1 l)
  body `[COMMUNITY]`, so the polynomials are plausible `[HYPOTHESIS]`.
- rossvz `[COMMUNITY]`, 34 oz bottle: full ≈ 37 mm, empty ≈ 237 mm; low
  `kcps` (< ~1000) means unreliable (tilted / obstructed).

Event classification (state machine over time-ordered log entries; our own
formulation of the published behaviour):

1. `v = clamp(poly(d), minVolume)`; if `d ≥ tofMax` → `SKIP` (keep state).
2. `Δfill = v − lastCalc`, `Δdrink = lastCounted − v`.
3. `Δfill > fillThreshold` → `FILL` (counted volume 0, except when the
   previous reading was skipped: count `lastCounted − lastSkipped` if > 0).
4. else `Δdrink > drinkThreshold` → `INTAKE` of `Δdrink` ml.
5. else `SKIP`, remember `lastSkipped = v`.
6. `lastCounted = v` on every non-skipped reading.

The default 680 ml/no-filter profile uses an independent measuring-cup fit;
see `calibration-680-nofilter.md`. Other profiles/configurations need their
own validation. Coefficients are parameters, not universal accuracy guarantees.

## 6. Connection lifecycle (what the BRITA app does) `[APP]`

1. Scan with service filter `0x180A`, match name containing `larq`.
2. Connect GATT, discover services.
3. Subscribe to NUS TX notifications; subscribe to Battery Level.
4. Send `SetCapTimeSettings(now_ms)`.
5. Realtime loop (remote-config gated): `READ_UI_STATE`,
   `READ_TOF_SETTINGS`, `READ_HYDRO_REMINDER_SETTINGS`,
   `READ_DO_NOT_DISTURB_SETTINGS`, `READ_LOW_BATTERY_SETTINGS`.
6. Event-log pull ("ELP"): for each log type, loop
   `fromTimestamp = latest stored`, `limit = 5` (ToF), until fewer than
   `limit` items return; upload.

BRITA's Data Act page describes roughly seven days of local retention.
The tested cap served much older history; do not infer a universal retention
limit from either observation. See the hardware notes.

## 7. Golden test vectors

Synthetic interoperability vectors cross-checked with `protoc 36.0` during
interface analysis. They contain no owner's device identity or activity log.
The codec must reproduce the specified wire bytes; the vendor schema itself
is not distributed.
Note proto3 default-value omission (enum value 0 and zero scalars are not
serialised).

```
# CapBleRequest{requestId:1, body:Any(RequestGetCapUiState{})}
0d01000000122a0a28747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617055695374617465

# CapBleRequest{requestId:7, body:Any(RequestSetCapTimeSettings{settings{timeInMillisec:1790000000000}})}
0d07000000123a0a2d747970652e676f6f676c65617069732e636f6d2f5265717565737453657443617054696d6553657474696e677312090a070880d8c1a28c34

# CapBleRequest{requestId:3, body:Any(RequestGetCapTofLog{query{fromTimestamp:1789999999, limit:5, algo:SEARCH_ALGO_TIMESTAMP}})}
0d0300000012380a27747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170546f664c6f67120d0a0b08fff6c4d5061505000000

# CapBleRequest{requestId:12, body:Any(RequestGetCapActivationLog{query{fromTimestamp:0, limit:6, algo:SEARCH_ALGO_TIMESTAMP}})}
0d0c00000012390a2e747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617041637469766174696f6e4c6f6712070a051506000000

# CapBleRequest{requestId:11, body:Any(RequestSetCapHydroReminderSettings{settings{state:REMINDER_STATE_OFF, startTimeInSec:1, stopTimeInSec:86400, intervalInSec:0, color{red:0, green:0, blue:1, alpha:1}}})}
0d0b00000012520a36747970652e676f6f676c65617069732e636f6d2f52657175657374536574436170487964726f52656d696e64657253657474696e677312180a1615010000001d805101002a0a1d0000803f250000803f

# CapBleResponse{requestId:1, code:SUCCESS, body:Any(ResponseGetCapUiState{state:UI_STATE_CHARGING, powerSavingMode:POWER_SAVING_MODE_OFF})}
0d0100000010011a310a29747970652e676f6f676c65617069732e636f6d2f526573706f6e736547657443617055695374617465120408081001

# CapBleResponse{requestId:3, code:SUCCESS, body:Any(ResponseGetCapTofLog{items[{ts:1790000100, TYPE_CAP, 120mm, kcps:6500, uvLedTempInOhm:10000.5}, {ts:1790000200, TYPE_INTERVAL, 135mm, kcps:6100, uvLedTempInOhm:9990.25}]})}
0d0300000010011a5e0a28747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f664c6f6712320a1708e4f7c4d50610021d7800000025641900002d00421c460a1708c8f8c4d50610011d8700000025d41700002d00191c46

# CapBleResponse{requestId:4, code:SUCCESS, body:Any(ResponseGetCapTofSettings{settings{mode:DISPLAY_MODE_EVENT, isIntervalTriggerEnabled:true, triggerIntervalInSec:300, accelerometerCheckIntervalInSec:5, bottleSizeInMilliliter:680, accelerometerTimeoutInSec:10}})}
0d0400000010011a4b0a2d747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f6653657474696e6773121a0a18080210011d2c01000025050000002da8020000350a000000

# CapBleResponse{requestId:5, code:SUCCESS, body:Any(ResponseGetCapHydroReminderSettings{settings{state:INTERVAL_FIXED, start:28800, stop:79200, interval:3600, color{1, 0.5, 0.25, 1}}})}
0d0500000010011a640a37747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170487964726f52656d696e64657253657474696e677312290a27080115807000001d6035010025100e00002a140d0000803f150000003f1d0000803e250000803f

# CapBleResponse{requestId:6, code:SUCCESS, body:Any(ResponseGetCapTofState{state{distanceInMillimeter:42, kcps:12000}})}
0d0600000010011a3a0a2a747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f665374617465120c0a0a0d2a00000015e02e0000

# CapBleResponse{requestId:8, code:SUCCESS, body:Any(ResponseGetCapLowBatterySettings{settings{alertThresholdInPercentage:20, lockoutThresholdInPercentage:5}})}
0d0800000010011a440a34747970652e676f6f676c65617069732e636f6d2f526573706f6e73654765744361704c6f774261747465727953657474696e6773120c0a0a0d140000001505000000

# CapBleResponse{requestId:10, code:SUCCESS, body:Any(ResponseGetCapActivationLog{items[{ts:1790000300, mode:UV_ACTIVATION_MAINTENANCE, batterySocInPercentage:87}]})}
0d0a00000010011a400a2f747970652e676f6f676c65617069732e636f6d2f526573706f6e736547657443617041637469766174696f6e4c6f67120d0a0b08acf9c4d5061d57000000

# CapBleResponse{requestId:9, code:NOT_SUPPORTED}  (no body)
0d090000001002
```

## 8. Verification and remaining limits

The tested cap confirmed service/name discovery, with-response writes,
Device Information, battery, paged logs, reminder/quiet-hour readback, and
operation without a vendor account. See `hw-session-1.md`.

Unverified configurations include filter-installed volume conversion, other
bottle bodies/firmware variants, condensation and temperature effects, and
universal sleep/retention behavior. Actual platform background execution and
notification delivery remain operating-system-dependent.
