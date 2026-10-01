#!/usr/bin/env python3
"""HydroCap calibration runner (host side).

One invocation = one calibration step. It triggers a full sync on the caller-selected Android device
(DEBUG_SYNC), waits for the engine's result line, pulls the Room database
(db + WAL) and appends every *new* tof_log row to the calibration CSV,
tagged with the step's known volume. Optionally also takes N "live" ToF
state reads (DEBUG_TOF) for comparison.

Usage:
  tools/calibrate.py --device <adb-serial-or-endpoint> --volume 0 --note "empty, straw only"
  tools/calibrate.py --device <adb-serial-or-endpoint> --volume 200 --live 3
  tools/calibrate.py --show                # print the CSV so far

Uses normal app sync (which may set the clock) and GetCapTofState only;
no calibration, factory-reset or firmware-update commands.
"""
import argparse, csv, json, os, re, sqlite3, subprocess, sys, tempfile, time
from datetime import datetime

DEVICE = os.environ.get("HYDROCAP_ADB")
PKG = "dev.hydrocap.app"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAPTURES = os.path.join(ROOT, "tools", "captures")
STATE = os.path.join(CAPTURES, "calibration-state.json")
FIELDS = ["step", "volume_ml", "filter", "kind", "timestamp", "time_local", "trigger_type",
          "distance_mm", "kcps", "uv_led_temp_ohm", "note"]


def adb(*args, timeout=60):
    if not DEVICE or not DEVICE.strip():
        raise ValueError("an explicit --device or HYDROCAP_ADB is required")
    return subprocess.run(["adb", "-s", DEVICE, *args], capture_output=True, text=True, timeout=timeout).stdout


def shell(cmd, timeout=60):
    return adb("shell", cmd, timeout=timeout)


def load_state():
    if os.path.exists(STATE):
        return json.load(open(STATE))
    return {"step": 0, "last_ts": 0, "csv": None, "filter": "none"}


def save_state(st):
    json.dump(st, open(STATE, "w"), indent=2)


def wait_for(pattern_done, pattern_fail, timeout_s):
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        log = shell("logcat -d -s HydroCap:V")
        if re.search(pattern_fail, log):
            return "fail", log
        if re.search(pattern_done, log):
            return "done", log
        time.sleep(2)
    return "timeout", shell("logcat -d -s HydroCap:V")


def run_sync():
    for attempt in (1, 2, 3):
        shell("input keyevent KEYCODE_WAKEUP; logcat -c")
        shell(f"am start -W -a {PKG}.action.DEBUG_SYNC -n {PKG}/.MainActivity >/dev/null")
        status, log = wait_for(r"\[sync\] sync done", r"\[sync\] ERROR|service job 'sync' ended with", 120)
        if status == "done":
            m = re.search(r"newTofEntries=(\d+)", log)
            return int(m.group(1)) if m else -1, log
        err = re.findall(r"\[sync\] ERROR.*", log)[-1:] or ["(no error line)"]
        print(f"  sync attempt {attempt}: {status} — {err[0][:120]}")
        time.sleep(8)
    sys.exit("sync failed three times")


def run_live(n):
    out = []
    for i in range(n):
        shell("logcat -c")
        shell(f"am start -W -a {PKG}.action.DEBUG_TOF -n {PKG}/.MainActivity >/dev/null")
        status, log = wait_for(r"live ToF distance=", r"\[sync\] ERROR|service job 'live_tof' ended with", 90)
        m = re.search(r"live ToF distance=(\d+) mm kcps=(\d+)", log)
        if status == "done" and m:
            out.append((int(m.group(1)), int(m.group(2))))
            print(f"  live {i + 1}/{n}: {m.group(1)} mm, kcps {m.group(2)}")
        else:
            print(f"  live {i + 1}/{n}: {status}")
        time.sleep(6)
    return out


def pull_db():
    if not DEVICE or not DEVICE.strip():
        raise ValueError("an explicit --device or HYDROCAP_ADB is required")
    d = tempfile.mkdtemp(prefix="hydrocap-cal-")
    for suffix in ("", "-wal", "-shm"):
        data = subprocess.run(["adb", "-s", DEVICE, "exec-out", f"run-as {PKG} cat databases/hydrocap.db{suffix}"],
                              capture_output=True, timeout=60).stdout
        if data and not data.startswith(b"cat:"):
            open(os.path.join(d, f"hydrocap.db{suffix}"), "wb").write(data)
    return os.path.join(d, "hydrocap.db")


def new_rows(db, since_ts):
    c = sqlite3.connect(db)
    rows = c.execute("select timestamp, triggerType, distanceMm, kcps, uvLedTempOhm from tof_log where timestamp > ? order by timestamp", (since_ts,)).fetchall()
    c.close()
    return rows


def main():
    global DEVICE
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default=DEVICE, help="explicit adb serial/endpoint; or set HYDROCAP_ADB")
    ap.add_argument("--volume", type=float, help="water in the bottle for this step, ml")
    ap.add_argument("--note", default="")
    ap.add_argument("--live", type=int, default=0, help="also take N GetCapTofState reads")
    ap.add_argument("--filter", choices=["none", "installed"], help="set filter state for this and following steps")
    ap.add_argument("--reset", action="store_true", help="start a new calibration session")
    ap.add_argument("--show", action="store_true")
    a = ap.parse_args()

    DEVICE = a.device
    if a.volume is not None and not a.show and (not DEVICE or not DEVICE.strip()):
        ap.error("--device or HYDROCAP_ADB is required for device operations")

    os.makedirs(CAPTURES, exist_ok=True)
    st = load_state()
    if a.reset or not st.get("csv"):
        st = {"step": 0, "last_ts": 0, "filter": "none",
              "csv": os.path.join(CAPTURES, f"calibration-{datetime.now():%Y-%m-%d-%H%M}.csv")}
        with open(st["csv"], "w", newline="") as f:
            csv.DictWriter(f, FIELDS).writeheader()
        save_state(st)
        print("new session:", st["csv"])
        if a.reset and a.volume is None:
            return
    if a.filter:
        st["filter"] = a.filter
    if a.show:
        print(open(st["csv"]).read())
        return
    if a.volume is None:
        sys.exit("--volume required")

    if st["last_ts"] == 0:
        # First step: take the current newest row as the baseline so only
        # rows produced from now on count.
        db = pull_db()
        c = sqlite3.connect(db)
        st["last_ts"] = c.execute("select coalesce(max(timestamp),0) from tof_log").fetchone()[0]
        c.close()

    st["step"] += 1
    step = st["step"]
    print(f"step {step}: volume={a.volume:g} ml filter={st['filter']} — syncing")
    n_new, log = run_sync()
    db = pull_db()
    rows = new_rows(db, st["last_ts"])
    print(f"  sync reported {n_new} new ToF entries; {len(rows)} new rows since last step")
    with open(st["csv"], "a", newline="") as f:
        w = csv.DictWriter(f, FIELDS)
        for ts, typ, mm, kcps, temp in rows:
            w.writerow({"step": step, "volume_ml": a.volume, "filter": st["filter"], "kind": "log",
                        "timestamp": ts, "time_local": datetime.fromtimestamp(ts).strftime("%H:%M:%S"),
                        "trigger_type": typ, "distance_mm": mm, "kcps": kcps, "uv_led_temp_ohm": temp, "note": a.note})
            print(f"  log  ts={ts} {datetime.fromtimestamp(ts):%H:%M:%S} type={typ} {mm} mm kcps={kcps} temp={temp}")
        if a.live:
            for mm, kcps in run_live(a.live):
                w.writerow({"step": step, "volume_ml": a.volume, "filter": st["filter"], "kind": "live",
                            "timestamp": int(time.time()), "time_local": datetime.now().strftime("%H:%M:%S"),
                            "trigger_type": "", "distance_mm": mm, "kcps": kcps, "uv_led_temp_ohm": "", "note": a.note})
    if rows:
        st["last_ts"] = max(r[0] for r in rows)
    else:
        print("  WARNING: no new log entry — cap did not measure (bottle moved? not set down? clock?)")
    save_state(st)


if __name__ == "__main__":
    main()
