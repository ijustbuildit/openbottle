# Android Health integration for the approved iOS UX

The Android companion uses **Health Connect**, not the retired Google Fit cloud API or a Google account. It retains the existing `HydrationRecord` writer and the Room `health_sync` versioned upsert plan; the target estimate additionally uses the optional `WeightRecord` read permission.

## Verified API facts

Checked against the official Android documentation and the exact `androidx.health.connect:connect-client:1.1.0` sources used by HydroCap:

- `WeightRecord` is instantaneous: `time`, nullable `zoneOffset`, `weight: Mass`, and metadata. The read permission is `android.permission.health.READ_WEIGHT`; weight is read in kilograms.
- `ReadRecordsRequest<WeightRecord>` supports descending time order, page size, continuation token, and `TimeRangeFilter`. Ignore future timestamps and non-positive/non-finite values rather than inventing a body measurement.
- Completed pagination can return either null or an empty token depending on provider/API version; use `pageToken.isNullOrEmpty()`.
- The fitness-record API has **no biological-sex or gender record** corresponding to HealthKit's characteristic. Do not confuse `SexualActivityRecord` with that field. HydroCap offers an optional manual sex fallback; it does not read account details or clinical records to manufacture parity.
- Standard read access extends back30days before the first grant of any Health Connect permission. Older data requires the separate historical-data permission; an unbounded query without it can fail. A bounded recent-weight lookup and explicit unavailable/manual fallback avoid requesting broader access merely for the goal estimate.
- Read access, hydration write access and actual available data are distinct. A user can deny hydration writes while permitting weight reads, or permit weight reads with no stored measurement. Neither situation blocks use of the bottle.

The goal remains the same editable adult **product estimate** as iOS: weight ×35ml/kg ×0.70, nearest50ml, product estimate bounds1.5–4L; the30%food allowance is an assumption, not a measured diet or a prescription. Manual goal override wins. These are not medical safety bounds. Source provenance and explanatory copy must remain visible.

## Sources

- [Health Connect data types](https://developer.android.com/health-and-fitness/health-connect/data-types)
- [Read data, pagination and historical-data restrictions](https://developer.android.com/health-and-fitness/health-connect/read-data)
- [WeightRecord reference](https://developer.android.com/reference/androidx/health/connect/client/records/WeightRecord)
- [Pinned1.1.0 source artifact](https://dl.google.com/dl/android/maven2/androidx/health/connect/connect-client/1.1.0/connect-client-1.1.0-sources.jar)

No additional cloud/account/network integration is required. Android's Health Connect consent/settings sheet and notification timing are OS-native differences, not replacement app UX.
