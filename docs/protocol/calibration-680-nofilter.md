# Calibration — 680 ml body, straw in, no filter

Sanitized observations: `data/calibration-680-nofilter.csv` (all 50 cap ToF
rows per fill level, including rejected ones). Absolute timestamps and local
clock times are replaced by elapsed seconds from the first observation;
volumes, distances, signal quality, temperature, triggers, notes, and intervals
are unchanged. Private raw originals are not distributed. Runner: `tools/calibrate.py`.

## Method

- Measuring cup, room-temperature tap water, filter pod empty, straw in.
- Per level: screw cap on, set down, wait ≥ 10–20 s; then flap open/close,
  set down, wait; repeat → 3–5 cap readings (`TYPE_CAP` = cap closed,
  `TYPE_CAP_ON_FLAP` / `_OPEN_SIP` = flap). Setting the bottle down alone
  does **not** trigger a reading; the accelerometer only gates *when* a
  cap/flap-triggered reading is taken (bottle at rest).
- Rejected: the first cap-close reading right after filling when it deviates
  > 6 mm from the flap readings (water still moving), and readings with kcps
  < 100 that also deviate > 6 mm from their neighbours (waves/drops: e.g.
  59 mm @ kcps 70 at 500 ml). Low kcps alone is *not* a rejection criterion
  (400 ml @ kcps 65 was consistent ±3 mm; 600 ml reads kcps ~23 consistently).

## Points used (mean of kept readings)

| ml | mm | sd | note |
|---|---|---|---|
| 0 | 207.3 | 0.5 | straw tip / sensor floor |
| 100 | 183.0 | 1.0 | |
| 200 | 160.7 | 0.5 | |
| 250 | 138.7 | 1.2 | control point, fresh fill |
| 300 | 121.3 | 1.2 | |
| 350 | 107.0 | 1.4 | "ca." |
| 400 | 93.5 | 1.0 | repeat; first 400 attempt read 103 mm = ~370 ml fill error, dropped |
| 450 | 77.3 | 0.9 | repeat; first attempt 61/68/79 waves, dropped |
| 500 | 68.4 | 1.0 | repeat; first attempt 59/70/76 waves, dropped |
| 600 | 36.7 | 0.5 | |
| 717 | 16.3 | 2.6 | brim (~715–720 ml by cup) |

Slope is ~23 mm/100 ml below 200 ml and ~30–35 mm/100 ml above 250 ml: the
body narrows towards the shoulder.

## Fit

Weighted (1/sd) cubic in d [mm]:

`V(d) = -6.208893338e-5·d³ + 0.02199185096·d² − 5.70134644·d + 791.0281811`

Residual RMSE 9.5 ml, max 16 ml, leave-one-out RMSE 15.5 ml, monotone on
0–230 mm, zero crossing at 208 mm. Degree 4 over-fits (LOO 27 ml), degree 2
under-fits at the brim (44 ml). Clamped to [0, 720] ml in the app;
`tofMaxMm = 230` (readings beyond are "sensor could not read").

Comparison — old LARQ 680 ml curve on the same readings: 22 ml at empty,
687 ml at brim, otherwise within ~25 ml. It had the volume roughly right and
the zero point wrong.

## Open

- Filter installed: displaces water in the pod → same distance = less water.
  Needs a separately validated curve or offset for the installed filter;
  the difference mostly cancels in intake deltas but shifts the fill estimate.
- Warm water / condensation on the sensor window: not characterised.
