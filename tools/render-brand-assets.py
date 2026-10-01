#!/usr/bin/env python3
"""Render the original editable HydroCap SVG; never consume a legacy raster.

Python 3 + Pillow and either CairoSVG or PyGObject/Rsvg/Pycairo.
Example: python3 tools/render-brand-assets.py
Uses existing librsvg/Cairo when available, otherwise CairoSVG. PNG encoding
has no timestamps/EXIF/text; outputs include only the explicit sRGB intent.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib
import io
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops, PngImagePlugin

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/brand/hydrocap-bottle.svg"
IOS = ROOT / "ios/HydroCap/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
REFERENCE = ROOT / "android/app/src/main/assets/ui-reference/hydrocap-icon-1024.png"
RES = ROOT / "android/app/src/main/res/drawable-nodpi"
ACCENT = (61, 158, 250)
SIZE = 1024
OUTPUTS = [IOS, REFERENCE, RES / "hydrocap_bottle.png", RES / "ic_launcher_art.png", RES / "ic_launcher_mono_art.png"]


def rasterize_svg() -> tuple[Image.Image, str]:
    """Render actual SVG at 4x, then downsample alpha for small-size quality."""
    data = SOURCE.read_bytes()
    svg = ET.fromstring(data)
    assert svg.attrib["viewBox"] == "0 0 1024 1024"
    mark = svg.find("{http://www.w3.org/2000/svg}g")
    assert mark is not None and mark.attrib.get("fill") == "#3D9EFA", "Keep the exact HydroCap accent in the editable source"
    assert not any(e.tag.endswith(("image", "text", "use")) for e in svg.iter()), "Artwork must stay self-contained vector paths"
    size = SIZE * 4
    try:
        import gi
        import cairo
        gi.require_version("Rsvg", "2.0")
        Rsvg = importlib.import_module("gi.repository.Rsvg")
    except (ImportError, ValueError):
        try:
            cairosvg = importlib.import_module("cairosvg")
        except ImportError as error:
            raise SystemExit("Install Python Pillow + CairoSVG, or use existing PyGObject/Rsvg/Pycairo; no Apple frameworks are used.") from error
        png = cairosvg.svg2png(bytestring=data, output_width=size, output_height=size)
        backend = "CairoSVG " + cairosvg.__version__
    else:
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
        context = cairo.Context(surface)
        handle = Rsvg.Handle.new_from_data(data)
        viewport = Rsvg.Rectangle()
        viewport.x = viewport.y = 0
        viewport.width = viewport.height = size
        assert handle.render_document(context, viewport), "SVG rendering failed"
        stream = io.BytesIO()
        surface.write_to_png(stream)
        png = stream.getvalue()
        backend = f"librsvg {Rsvg.MAJOR_VERSION}.{Rsvg.MINOR_VERSION}.{Rsvg.MICRO_VERSION} / Cairo {cairo.cairo_version_string()}"
    alpha = Image.open(io.BytesIO(png)).convert("RGBA").getchannel("A").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    art = Image.new("RGBA", (SIZE, SIZE), (*ACCENT, 0))
    art.putalpha(alpha)
    return art, backend


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    info = PngImagePlugin.PngInfo()
    info.add(b"sRGB", b"\x00")
    image.save(path, format="PNG", pnginfo=info, optimize=False, compress_level=9)


def verify(paths: list[Path]) -> dict:
    results = []
    for path in paths:
        with Image.open(path) as image:
            image.load()
            assert image.info == {"srgb": 0}, (path, image.info)
            assert not image.getexif(), f"Unexpected EXIF: {path}"
            alpha = image.getchannel("A") if image.mode == "RGBA" else None
            results.append({"path": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
                            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                            "size": list(image.size), "mode": image.mode,
                            "alpha_extrema": list(alpha.getextrema()) if alpha else None,
                            "alpha_bounds": list(alpha.getbbox()) if alpha else None,
                            "metadata": image.info})
    return {"outputs": results}


def render_all(ios_output: Path = IOS, ios_only: bool = False) -> dict:
    art, backend = rasterize_svg()
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    icon = Image.alpha_composite(Image.new("RGBA", art.size, "white"), art).convert("RGB")
    assert icon.size == (1024, 1024) and icon.mode == "RGB"
    assert icon.getpixel((0, 0)) == (255, 255, 255)
    assert icon.getpixel((512, 760)) == ACCENT
    save_png(icon, ios_output)
    if ios_only:
        return {"source_sha256": source_hash, "renderer": backend, **verify([ios_output])}
    save_png(icon, REFERENCE)
    bounds = art.getchannel("A").getbbox()
    assert bounds
    save_png(art.crop(bounds), RES / "hydrocap_bottle.png")
    save_png(art, RES / "ic_launcher_art.png")
    mono = Image.new("RGBA", art.size, (255, 255, 255, 0))
    mono.putalpha(art.getchannel("A"))
    save_png(mono, RES / "ic_launcher_mono_art.png")
    assert ios_output.read_bytes() == REFERENCE.read_bytes()
    assert Image.alpha_composite(Image.new("RGBA", art.size, "white"), Image.open(RES / "ic_launcher_art.png")).convert("RGB").tobytes() == icon.tobytes()
    assert Image.open(RES / "ic_launcher_mono_art.png").getchannel("A").tobytes() == art.getchannel("A").tobytes()
    assert Image.open(RES / "hydrocap_bottle.png").tobytes() == art.crop(bounds).tobytes()
    # Read the retained launcher resources rather than assuming their mapping.
    android_attr = "{http://schemas.android.com/apk/res/android}"
    layer_root = ROOT / "android/app/src/main/res"
    adaptive = ET.parse(layer_root / "mipmap-anydpi/ic_launcher.xml").getroot()
    assert adaptive.tag == "adaptive-icon"
    for tag, resource in [("background", "@android:color/white"),
                          ("foreground", "@drawable/ic_launcher_foreground"),
                          ("monochrome", "@drawable/ic_launcher_monochrome")]:
        child = adaptive.find(tag)
        assert child is not None and child.attrib[android_attr + "drawable"] == resource
    for name, raster in [("ic_launcher_foreground", "ic_launcher_art"),
                         ("ic_launcher_monochrome", "ic_launcher_mono_art")]:
        wrapper = ET.parse(layer_root / "drawable" / f"{name}.xml").getroot()
        assert wrapper.tag == "inset" and wrapper.attrib[android_attr + "inset"] == "16.6667%"
        bitmap = wrapper.find("bitmap")
        assert bitmap is not None and bitmap.attrib[android_attr + "src"] == f"@drawable/{raster}"
        assert bitmap.attrib[android_attr + "gravity"] == "fill"
    # Existing Android wrapper maps this 1024px canvas into the central 72dp
    # of the adaptive layer's 108dp canvas. Every alpha pixel must be inside
    # its guaranteed 66dp-diameter safe circle, not merely its square bounds.
    safe_alpha = art.getchannel("A")
    max_radius_squared = 0.0
    for y in range(SIZE):
        for x in range(SIZE):
            if safe_alpha.getpixel((x, y)):
                dx = (x + 0.5 - SIZE / 2) * 72 / SIZE
                dy = (y + 0.5 - SIZE / 2) * 72 / SIZE
                max_radius_squared = max(max_radius_squared, dx * dx + dy * dy)
    radius = max_radius_squared ** 0.5
    assert radius <= 33, f"Adaptive safe circle exceeded: {radius}dp"
    return {"source": str(SOURCE.relative_to(ROOT)), "source_sha256": source_hash, "renderer": backend,
            "normal_composite_pixel_exact": True, "monochrome_alpha_exact": True,
            "ui_glyph_exact_crop": True, "adaptive_wrapper_inset": "16.6667%",
            "safe_circle_radius_dp": 33, "max_art_radius_dp": round(radius, 6),
            **verify([ios_output, *OUTPUTS[1:]])}


def contact_sheet(path: Path) -> None:
    """Inspection-only launcher simulations, never platform screenshots."""
    from PIL import ImageDraw, ImageFont
    canvas = Image.new("RGB", (1600, 1370), "#edf0f4")
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 17)
    except OSError:
        font = ImageFont.load_default()
    icon = Image.open(IOS).convert("RGBA")
    art = Image.open(RES / "ic_launcher_art.png").convert("RGBA")
    mono = Image.open(RES / "ic_launcher_mono_art.png").convert("RGBA")
    glyph = Image.open(RES / "hydrocap_bottle.png").convert("RGBA")
    draw.text((24, 14), "HydroCap original vector • 1024px / launcher 48px + 24px / UI glyph 48px + 24px", fill="#152334", font=font)
    canvas.paste(icon.convert("RGB"), (24, 48))
    draw.text((24, 1080), "1024px opaque iOS master • #3D9EFA on white • no pre-rounded corners", fill="#152334", font=font)
    labels = [("Light launcher", "#e8edf3", "#ffffff", ACCENT),
              ("Dark launcher", "#171e29", "#ffffff", ACCENT),
              ("Themed light", "#e8edf3", "#d4e5fb", (24, 70, 113)),
              ("Themed dark", "#171e29", "#23455f", (170, 210, 252))]
    for row, (label, surface, background, ink) in enumerate(labels):
        px, py = 1080, 48 + row * 256
        draw.rounded_rectangle((px, py, px + 494, py + 230), radius=20, fill=surface)
        text_color = "#eef4fc" if "dark" in label.lower() else "#152334"
        draw.text((px + 18, py + 12), label + " · simulated circle mask", fill=text_color, font=font)
        layer = art if row < 2 else Image.new("RGBA", art.size, (*ink, 0))
        if row >= 2:
            layer.putalpha(mono.getchannel("A"))
        composed = Image.alpha_composite(Image.new("RGBA", art.size, background), layer)
        for size, offset in [(48, 0), (24, 235)]:
            preview = composed.resize((size, size), Image.Resampling.LANCZOS)
            mask = Image.new("L", (size * 4, size * 4), 0)
            ImageDraw.Draw(mask).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
            preview.putalpha(mask.resize((size, size), Image.Resampling.LANCZOS))
            x, y = px + 20 + offset, py + 55
            canvas.paste(preview, (x, y), preview)
            enlarged = preview.resize((size * 2, size * 2), Image.Resampling.NEAREST)
            canvas.paste(enlarged, (x + 70, y), enlarged)
            draw.text((x, py + 175), f"{size}px + 2x pixels", fill=text_color, font=font)
    for row, background in enumerate(("#ffffff", "#171e29")):
        px, py = 24 + row * 770, 1140
        draw.rounded_rectangle((px, py, px + 742, py + 205), radius=16, fill=background)
        fg = "#152334" if row == 0 else "#eef4fc"
        draw.text((px + 18, py + 12), "UI glyph (transparent cutout, untinted blue) · " + ("light" if row == 0 else "dark"), fill=fg, font=font)
        for size, offset in [(48, 0), (24, 350)]:
            g = glyph.copy()
            g.thumbnail((size, size), Image.Resampling.LANCZOS)
            x, y = px + 22 + offset, py + 52
            canvas.paste(g, (x, y), g)
            zoom = g.resize((g.width * 2, g.height * 2), Image.Resampling.NEAREST)
            canvas.paste(zoom, (x + 80, y), zoom)
            draw.text((x, py + 163), f"{size}px box + 2x pixels", fill=fg, font=font)
    save_png(canvas, path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios-output", type=Path, default=IOS)
    parser.add_argument("--ios-only", action="store_true")
    parser.add_argument("--contact-sheet", type=Path)
    args = parser.parse_args()
    result = render_all(args.ios_output.resolve(), args.ios_only)
    if args.contact_sheet:
        if args.ios_only:
            parser.error("--contact-sheet requires all platform assets")
        contact_sheet(args.contact_sheet.resolve())
        result["contact_sheet"] = str(args.contact_sheet.resolve())
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
