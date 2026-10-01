# Native Android UI assets

## Bottle artwork

The editable original is [`../assets/brand/hydrocap-bottle.svg`](../assets/brand/hydrocap-bottle.svg), with construction and licensing documented in [`../assets/brand/PROVENANCE.md`](../assets/brand/PROVENANCE.md). It is independently authored artwork: right-offset neck, slanted detached cap, asymmetric shoulders, broad tapered body and a transparent water-wave cutout. It contains no SF Symbols, traced predecessors, Apple font glyphs or BRITA/LARQ artwork. The original artwork and its rasters use the repository's PolyForm Noncommercial1.0.0 license; this is not a trademark-clearance opinion.

Run `python3 tools/render-brand-assets.py` or the retained `python3 tools/generate-android-icon.py` **from the repository root**. Python3 + Pillow and either installed librsvg/Pycairo/PyGObject or CairoSVG render the SVG directly; no legacy PNG is an input. The shared renderer regenerates all five linked PNGs and verifies:

- `app/src/main/assets/ui-reference/hydrocap-icon-1024.png` is byte-identical to the opaque1024×1024 RGB iOS icon: full-bleed white with exact accent **#3D9EFA**, no pre-rounded corners.
- `ic_launcher_art.png` is a transparent1024×1024 RGBA adaptive foreground; its white composite matches the iOS master pixel-for-pixel.
- `ic_launcher_mono_art.png` has exactly the same alpha, including the water cutout, with white RGB for launcher-controlled monochrome tint.
- `hydrocap_bottle.png` is a tightly cropped RGBA inline glyph from the same original SVG render. The existing Compose `Image` keeps its blue artwork and transparent hole on either UI theme; unlike other `HydroIcon` vectors, it does not receive `Icon` tint.
- PNGs contain only the explicit sRGB rendering intent, no inherited EXIF or Apple metadata.

Resource names and launcher XML remain unchanged. The existing16.6667% inset maps art into the central72dp of the108dp adaptive layer; every nonzero-alpha pixel is checked inside the guaranteed66dp-diameter safe circle for **both** normal and monochrome. The adaptive XML supports normal and themed launcher modes without legacy square fallbacks (minSdk29). Android10 ignoring the newer monochrome child is a previously recorded inflater check, not a new device test in this artwork change.

`python3 tools/render-brand-assets.py --contact-sheet /tmp/hydrocap-original-icon-contact-sheet.png` additionally produces inspection-only light/dark and themed launcher simulations plus48px/24px UI samples. Actual launcher masking/parallax remains platform-controlled. Public/store review, app builds and device validation remain separate.

## Rounded display numerals

`res/font/hydrocap_numbers.ttf` is the **unmodified Nunito variable font** from the Google Fonts repository. It is used only for rounded display numerals, not to replace the native system text throughout the app or to redistribute Apple fonts. The pinned downloaded bytes have SHA256 `bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207`.

- Source: https://raw.githubusercontent.com/google/fonts/main/ofl/nunito/Nunito%5Bwght%5D.ttf
- License: SIL Open Font License1.1, copyright2014 The Nunito Project Authors.
- Complete required notice is packaged in `app/src/main/assets/licenses/Nunito-OFL.txt`.

Android-native font rendering and Health Connect/system permission sheets differ from iOS. The parity contract preserves the approved hierarchy, layout, accent, shapes and behavior without bundling Apple's private font/framework implementation.
