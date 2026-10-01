# Prior art and evidence sources (retrieved 2026-09-28)

## Product

- BRITA LARQ iQ product page (DE): https://www.brita.de/produkte/brita-larq-iq-filter-trinkflasche
  — sizes 680 ml / 1000 ml, "eine volle Akkuladung hält für 2–3 Wochen", USB-C
  cap, BRITA app required "für das volle Potenzial".
- BRITA Data Act page: https://www.brita.de/data-act-angaben — cap stores
  ~7 days locally (oldest overwritten), cloud on Azure Europe-West, data
  exported as JSON/CSV, API key on request.
- BRITA acquired LARQ, Inc. in Feb 2024:
  https://techcrunch.com/2024/02/07/brita-snaps-up-smart-water-bottle-startup-larq/
- BRITA app (iOS, id6740991153): 3.5★ / 32 ratings (DE store, 2026-09-28),
  v1.1.3, min iOS 17. Android package `com.brita.britaapp`.
- Review by appgefahren (2025-08-16): account mandatory, tracking not
  always reliable, straw-only:
  https://www.appgefahren.de/brita-larq-iq-filter-trinkflasche-mit-app-tracking-im-test-384556.html

## User complaints (App Store reviews, 28 reviews across 12 storefronts)

Recurring themes: mandatory account; tracking only while app is open /
missing sips; Apple Health sync broken or partial; wants push
notifications on phone/watch; internet required; no widget; inaccurate
volumes. Quote (GB, 2026-05-31): "The Larq app was bad, somehow they've
made this worse". Raw export: kept outside the repo (private research
cache).

## Open-source / community

| Project | What | Licence | Useful for |
|---|---|---|---|
| https://github.com/albi005/bottle | Android app: BLE → ToF logs → Health Connect (PureVis 2) | none | protocol confirmation, algorithm description |
| https://github.com/rossvz/larq-tui | Node/Bun daemon + TUI, protocol docs | none | sleep/one-request-at-a-time/KCPS observations, full/empty mm |
| https://github.com/kasim141-a/hass-larq | Home Assistant: BLE battery + Firebase hydration | none | battery via `0x2A19` confirmed |
| https://github.com/lavyyy/openlarq | self-hosted dashboard for LARQ cloud | MIT | not relevant (cloud) |
| HA forum thread: https://community.home-assistant.io/t/larq-smart-bottle-integration-hydration-tracking-ble-battery-in-ha/1009801 | "protobuf over BLE… completely zero authentication" | — | confirms no auth |

None of these targets the BRITA iQ cap explicitly; all were tested on
LARQ PureVis 2 hardware. The BRITA app 1.1.0 uses the identical
`com.product.core_ble` stack and `LARQ_` naming, so the protocol is
expected to be the same. To be verified on hardware.
