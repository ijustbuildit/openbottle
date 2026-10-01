# Original HydroCap bottle mark

## Provenance

`hydrocap-bottle.svg` is the editable master. Its geometry was independently authored for HydroCap, using manually chosen cubic Bézier paths rather than a stock symbol, font glyph, traced image, vendor silhouette or generated derivative of the previous icon. The previous PNGs were not used as rendering inputs or inspected as design templates.

Distinctive construction:
- A short neck offset to the right of the body centre.
- A detached cap with a rising diagonal top and matching diagonal closure.
- Unequal shoulders: one long inclined shoulder and one short curved shoulder.
- A broad, gently tapered body with a rounded flat base.
- An enclosed, rising water-wave cutout, transparent in the normal and monochrome marks.

The generic idea of a blue water bottle is retained; the paths, proportions and silhouette are newly constructed. No Apple SF Symbols, Apple fonts, BRITA/LARQ marks or third-party artwork are included. This provenance documents construction, not a trademark search or a legal clearance opinion.

## License

This original artwork and its generated HydroCap rasters are covered by the repository's **PolyForm Noncommercial 1.0.0** license; see [`../../LICENSE`](../../LICENSE). The repository owner maintains the canonical license and notices. No separate permissive artwork grant is made here.

## Reproduction

From the repository root:

```sh
python3 tools/render-brand-assets.py
# Retained Android entry point (same shared renderer):
python3 tools/generate-android-icon.py
# Inspection-only contact sheet, kept outside the repository:
python3 tools/render-brand-assets.py --contact-sheet /tmp/hydrocap-original-icon-contact-sheet.png
```

Requirements: Python 3, Pillow, and either PyGObject/Rsvg/Pycairo or CairoSVG. The renderer uses existing librsvg/Cairo first and otherwise CairoSVG. No Apple framework, system-symbol extraction or old raster is needed. For byte-identical regeneration use the same renderer versions; different SVG engines may differ in edge antialiasing while retaining the same geometry.

`ios/scripts/render_app_icon.swift` is only a macOS compatibility wrapper for the portable Python renderer. Its optional first argument selects an iOS-only output path; the preferred Python command regenerates all five linked rasters together.

## Output contracts

- iOS master: 1024×1024, opaque RGB, full-bleed white, blue **#3D9EFA**. No rounded-corner mask baked in.
- Android reference: the identical iOS PNG bytes at `android/app/src/main/assets/ui-reference/hydrocap-icon-1024.png`.
- Android normal adaptive art: 1024×1024 RGBA, constant blue RGB and antialiased alpha. Compositing over white exactly reproduces iOS pixels.
- Android themed art: 1024×1024 RGBA, white RGB and the exact same alpha including the wave cutout; the launcher supplies the tint.
- Android inline bottle: tightly cropped transparent blue mark from the same SVG render. Existing Compose `Image` preserves the accent rather than applying `Icon` tint.
- Existing launcher wrappers use a 16.6667% inset. This maps the art to the central72dp of a108dp adaptive layer; the renderer verifies every nonzero-alpha pixel fits within the guaranteed66dp-diameter safe circle.
- PNG metadata is only explicit sRGB rendering intent; no EXIF, timestamps, author text, GPS or Apple source metadata.

The private inspection report, contact sheet, verification JSON and hashes belong in `/tmp`, not the artwork directory.
