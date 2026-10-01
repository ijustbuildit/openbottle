#!/usr/bin/env python3
"""Regenerate original HydroCap iOS/Android artwork from the editable SVG.

Retained entry point: python3 tools/generate-android-icon.py
Optional flags (including --contact-sheet) are forwarded to the shared renderer.
Never reads, traces, extracts or recolours the old SF-derived icon.
"""
from pathlib import Path
import runpy

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).with_name("render-brand-assets.py")), run_name="__main__")
