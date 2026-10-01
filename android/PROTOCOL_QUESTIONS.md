# Android protocol implementation notes

These notes clarify the independent implementation and its evidence limits. See [protocol specification](../docs/protocol/ble-protocol.md), [hardware observations](../docs/protocol/hw-session-1.md), and [calibration](../docs/protocol/calibration-680-nofilter.md).

- **Identity:** BLE addresses are transient. Rescan before connecting; retain stable name/decoded serial only after usable readiness. Public fixtures use generated identities.
- **Capacity:** `bottleSizeInMilliliter` is informational. The observed capacity field disagreed with the physical small bottle; never auto-select a profile from it.
- **Paging:** stop on an empty/short page or a non-advancing cursor. Do not let duplicate/unordered pages create an infinite import loop.
- **Volume state:** an out-of-range ToF observation leaves the usable state untouched. A usable below-threshold/jitter observation may seed the fill-after-skip calculation. The first usable reading initializes state without inventing a drink.
- **Responses:** request IDs correlate one outstanding request. `FAIL` / `NOT_SUPPORTED` are answered failures, not timeout-retry evidence; timeouts use the bounded retry policy.
- **Battery:** if a firmware lacks a Battery CCCD, a normal GATT read remains useful; do not silently claim that every firmware notifies battery changes.
- **Unknown enums:** preserve numeric unknown values rather than copying a full vendor table unrelated to the supported interface.
- **Quiet hours:** AUTO derives its start/stop from the complementary reminder window; settings are read back from the cap. The snooze value is preserved unchanged; broader firmware behavior is not universally characterized.
- **Reminder color:** RGB zero denotes firmware-default color, not necessarily black. Controlled nonzero color writes/readback were exercised on the tested cap. The app exposes this defined reminder configuration, not arbitrary LED animation.
- **Time representation:** valid settings use seconds of day 1 through 86400, with midnight represented by 86400. Overnight windows are valid; unknown/invalid hours must not silently become a default daytime notification window.

The command allowlist remains authoritative. No reset, DFU, UV, cap-calibration, or unrestricted setter is implemented.
