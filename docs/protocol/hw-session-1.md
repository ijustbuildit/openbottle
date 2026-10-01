# Hardware interoperability observations

Sanitized observations from an owner-authorized BRITA LARQ iQ cap test. This document retains interface/measurement facts, not the owner's cap serial, BLE addresses, absolute activity times, or personal drinking history. Raw capture originals are not distributed.

`[HW]` denotes an observation on the tested cap/configuration, not a guarantee for every firmware or LARQ-family product.

## Discovery and identity `[HW]`

- The advertisement included Device Information service `0x180A`, a `LARQ_` name with a base62 suffix, and Nordic manufacturer data `0x0059` followed by ASCII `CAP`.
- Decoding the suffix produced the same identity as Device Information's Serial Number String. Public test examples use generated identities instead of the observed serial.
- The BLE address changed between connections. Persisting a MAC was unreliable; scan afresh and match the stable advertised/decoded identity.
- Advertising continued across several idle minutes in the observed configuration. Community reports of a short sleep timeout may depend on state/firmware; do not present a fixed sleep timeout as universal.
- Android's service-filtered scanning worked in circumstances where an unfiltered background scan was restricted.

## GATT and transport `[HW]`

- Android accepted a requested ATT MTU of 247. A 179-byte ToF response arrived as one notification; bounded fragment reassembly remains necessary as a fallback on other stacks.
- Device Information, Battery Service, and Nordic UART characteristics matched the protocol specification.
- NUS RX supported write and write-without-response; NUS TX supported notifications. Writes with response worked on the tested cap.
- Manufacturer/model strings identified the LARQ CAP family. Battery Level `0x2A19` was readable and notifiable without a bonding workflow.
- A DFU service was observed but never used by OpenBottle.
- Request IDs were echoed correctly. Ordinary replies were fast, while an on-demand ToF measurement could take longer; fixed timing is not guaranteed.

## Interface behavior `[HW]`

- ToF settings reported a 1000 ml capacity despite a confirmed physical 680 ml bottle. The app therefore keeps bottle profile selection separate from this informational field.
- The cap exposed live ToF distance and signal-quality values, paged ToF history, activation/battery history, reminder settings, quiet hours, and clock settings.
- A success response with no body terminated paged logs. It is a normal end-of-history result, not an envelope error.
- Stored logs covered a much longer period than a simple seven-day assumption. Actual retention depends on capacity/use/firmware; do not promise a fixed history length.
- The observed cap clock was not current before synchronization. The normal app connection workflow sets the clock before importing further measurements; historical drifted timestamps are not magically corrected.
- Reminder RGB values of zero represented the firmware-default color. Later controlled reminder/color writes and readback were exercised successfully; this is not an unrestricted LED-control API.
- Reminder and quiet-hour writes are read back after Apply. Automatic quiet hours use the complementary reminder window; the current cap remains the source of truth.

## Implementation consequences

1. Rescan before each connection and bind pairing to usable readiness plus stable identity—not transient address.
2. Enable notifications/read Device Information before announcing successful pairing. Continue first history import on the same app-owned job while navigation is available.
3. Set clock time through the allowed workflow. A UI operation described as a “read” can therefore include this normal clock synchronization; zero-write probes are a separate tool mode.
4. Keep manual bottle profile selection; use the [measuring-cup calibration](calibration-680-nofilter.md) only for the physical setup it describes.
5. Preserve one outstanding request, ID correlation, bounded framing/reassembly, and the cap-command allowlist.
6. Treat BLE/Health/UI/background/notification verification as separate evidence layers. A synthetic fixture proves protocol logic, not live hardware success.

See [BLE protocol](ble-protocol.md) for field definitions and synthetic golden vectors.
