#!/usr/bin/env python3
"""HydroCap dev tool: run frida_ble_scan.js inside a host process on the rooted
phone and keep the session alive until the script reports SCAN_STOPPED.

Usage: frida_ble_scan.py --host <frida-endpoint> --process <host-process> [--seconds 30]
HYDROCAP_FRIDA_HOST and HYDROCAP_FRIDA_PROCESS may supply those explicit selections.
Read-only: passive BLE scan, no connections, no writes.
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path


HERE = Path(__file__).resolve().parent


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default=os.environ.get("HYDROCAP_FRIDA_HOST"))
    ap.add_argument("--process", default=os.environ.get("HYDROCAP_FRIDA_PROCESS"))
    ap.add_argument("--seconds", type=int, default=30)
    ap.add_argument("--out", default=None, help="append JSON lines here as well")
    ap.add_argument("--spawn", action="store_true", help="spawn --process instead of attaching")
    args = ap.parse_args()

    if not args.host or not args.host.strip():
        ap.error("--host or HYDROCAP_FRIDA_HOST is required")
    if not args.process or not args.process.strip():
        ap.error("--process or HYDROCAP_FRIDA_PROCESS is required")
    import frida

    dev = frida.get_device_manager().add_remote_device(args.host)
    if args.spawn:
        pid = dev.spawn([args.process])
        session = dev.attach(pid)
    else:
        session = dev.attach(args.process)
    src = (HERE / "frida_ble_scan.js").read_text()
    script = session.create_script(src, runtime="v8")
    done = {"stopped": False}
    out = open(args.out, "a") if args.out else None

    def on_message(msg, data):
        if msg.get("type") == "send":
            payload = msg.get("payload")
        elif msg.get("type") == "error":
            payload = "JS_ERROR " + str(msg.get("description")) + "\n" + str(msg.get("stack"))
        else:
            payload = msg
        line = payload if isinstance(payload, str) else json.dumps(payload)
        print(line, flush=True)
        if out:
            out.write(line + "\n"); out.flush()
        if isinstance(line, str) and "SCAN_STOPPED" in line:
            done["stopped"] = True

    script.on("message", on_message)
    # console.log() arrives as message type "log"
    def on_log(level, text):
        print(text, flush=True)
        if out:
            out.write(text + "\n"); out.flush()
        if "SCAN_STOPPED" in text:
            done["stopped"] = True
    script.set_log_handler(on_log)
    script.load()
    if args.spawn:
        dev.resume(pid)
    deadline = time.time() + args.seconds
    while not done["stopped"] and time.time() < deadline:
        time.sleep(0.2)
    try:
        script.unload()
    except Exception:
        pass
    session.detach()
    return 0


if __name__ == "__main__":
    sys.exit(main())
