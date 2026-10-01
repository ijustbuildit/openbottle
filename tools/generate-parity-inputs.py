#!/usr/bin/env python3
"""Explicitly synthetic parity inputs; expected values come from native Swift."""
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo
import hashlib
import itertools
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "android/app/src/test/resources/parity"
OUT.mkdir(parents=True, exist_ok=True)


def epoch(iso, zone):
    return int(datetime.fromisoformat(iso).replace(tzinfo=ZoneInfo(zone)).timestamp())


def write(name, rows):
    (OUT / name).write_text("# Explicitly synthetic inputs; expected values executed by untouched iOS production sources.\n" +
                           "\n".join("\t".join(map(str, row)) for row in rows) + "\n")


def main():
    targets = []
    for i, weight in enumerate(["nil", "0", "-1", "NaN", "Infinity", "1", "50", "61.25", "70", "75", "80", "95", "120", "200"]):
        for sex in ["nil", "female", "male", "other"]:
            targets.append((f"target-{i}-{sex}", "true", "nil", weight, sex, "68.5", "female"))
    for i, override in enumerate([-2000, 500, 524, 525, 1999, 2000, 2025, 5975, 6000, 999999]):
        targets.append((f"override-{i}", "false", override, "85", "male", "60", "female"))
    targets.extend([("default", "true", "nil", "nil", "nil", "nil", "nil"),
                    ("manual-weight", "true", "nil", "nil", "male", "68.5", "female"),
                    ("manual-sex", "true", "nil", "nil", "nil", "nil", "male"),
                    ("estimate-off-no-value", "false", "nil", "70", "female", "nil", "nil")])
    write("target-input.tsv", targets)

    history = []
    days_by_range = {"1d": 1, "7d": 7, "30d": 30, "90d": 90, "1y": 370}
    bases = [("ordinary-de", "2026-09-30T13:35:00", "Europe/Berlin", "de-DE"),
             ("ordinary-us", "2026-09-30T13:35:00", "America/New_York", "en-US"),
             ("spring-de", "2026-03-29T13:35:00", "Europe/Berlin", "de-DE"),
             ("fall-de", "2026-10-25T13:35:00", "Europe/Berlin", "de-DE"),
             ("spring-us", "2026-03-08T13:35:00", "America/New_York", "en-US"),
             ("fall-us", "2026-11-01T13:35:00", "America/New_York", "en-US"),
             ("leap-edge", "2024-02-28T13:35:00", "UTC", "de-DE"),
             ("leap-day", "2024-02-29T13:35:00", "Europe/Berlin", "de-DE"),
             ("month-edge", "2026-05-01T13:35:00", "Europe/Berlin", "de-DE")]
    for tag, iso, zone, locale in bases:
        z = ZoneInfo(zone)
        now = datetime.fromisoformat(iso).replace(tzinfo=z)
        midnight = now.replace(hour=0, minute=0, second=0)
        for range_, length in days_by_range.items():
            events = []
            for day in range(length + 1):
                local = midnight - timedelta(days=day)
                # Several drinks count once; missing and explicit0days never lower averages.
                if day % 7 == 0:
                    events.append((int((local + timedelta(hours=8)).timestamp()), 0))
                elif day % 5 != 0:
                    events.extend([(int((local + timedelta(hours=8)).timestamp()), 100 + day * 3),
                                   (int((local + timedelta(hours=10)).timestamp()), 200 + day * 7)])
            if tag.startswith("fall"):
                repeated = midnight.replace(hour=2 if zone == "Europe/Berlin" else 1, minute=30)
                events.extend([(int(repeated.replace(fold=0).timestamp()), 111),
                               (int(repeated.replace(fold=1).timestamp()), 222)])
            events.extend([(int(now.timestamp()), 17), (int((now + timedelta(hours=1)).timestamp()), 999)])
            event_text = ";".join(f"{ts}:{ml}" for ts, ml in sorted(events))
            history.append((f"{tag}-{range_}", range_, int(now.timestamp()), zone, locale, 2000, event_text))
    for range_ in days_by_range:
        history.append((f"empty-{range_}", range_, epoch("2026-09-30T13:35:00", "Europe/Berlin"), "Europe/Berlin", "de-DE", 2000, "nil"))
    write("history-input.tsv", history)

    reminders = []
    bases = [("normal", "2026-09-30T11:17:00", "Europe/Berlin"),
             ("spring", "2026-03-29T00:01:00", "Europe/Berlin"),
             ("fall", "2026-10-25T00:01:00", "Europe/Berlin"),
             ("late", "2026-09-30T23:40:00", "Europe/Berlin")]
    for (tag, iso, zone), (start, stop), (frequency, consumed, behind) in itertools.product(
        bases, [(28800, 79200), (79200, 28800), (86400, 28800), (5400, 18000)],
        [(60, 0, "true"), (90, 350, "true"), (120, 2000, "true"), (180, 0, "false")]):
        reminders.append((f"{tag}-{start}-{stop}-{frequency}-{behind}", epoch(iso, zone), zone,
                          start, stop, frequency, 2000, consumed, "true", behind))
    for i, (start, stop, frequency, enabled) in enumerate([(0, 79200, 120, "true"), (28800, 28800, 120, "true"),
                                                         (28800, 79200, 0, "true"), (28800, 79200, 120, "false")]):
        reminders.append((f"invalid-{i}", epoch("2026-09-30T11:17:00", "Europe/Berlin"), "Europe/Berlin", start, stop, frequency, 2000, 0, enabled, "true"))
    write("reminder-input.tsv", reminders)
    sources = ["ios/HydroCap/Data/Records.swift", "ios/HydroCap/Domain/HydrationTarget.swift",
               "ios/HydroCap/Domain/HistoryAggregation.swift", "ios/HydroCap/Domain/ReminderConfig.swift",
               "ios/HydroCap/Notify/DrinkReminderPlanner.swift", "tools/ios-parity-reference.swift"]
    manifest = {"reference_commit": None,
                "baseline_reference_commit": "0d2011e902a3ca4d61df6822f348176002a9c2ef",
                "reference_revision": "dynamic-y-axis-v1",
                "reference_identity": "Exact source_sha256 of the current sanitized production snapshot; no unchanged-commit claim.",
                "synthetic": True,
                "source_sha256": {s: hashlib.sha256((ROOT / s).read_bytes()).hexdigest() for s in sources},
                "case_counts": {"targets": len(targets), "history": len(history), "reminders": len(reminders)},
                "generation": "Inputs generated with Python; expected values MUST be executed by native Swift CLI against these source hashes."}
    (OUT / "reference-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
