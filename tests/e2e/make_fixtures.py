"""Builds the small input files the e2e tests feed to the tools.

Usage: make_fixtures.py noisy|scan|signature|slides OUTPUT
Runs in the signer's venv (PyMuPDF + Pillow); nothing binary is committed.
"""

import argparse
import random
from pathlib import Path

import pymupdf
from PIL import Image, ImageDraw

# Any TTF with Cyrillic glyphs; the scan fixture needs one to be OCR-able.
CYRILLIC_FONTS = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
)
SCAN_LINES = ("Підписант:", "ОЛЕКСІЙ СЕДУН", "Начальник відділу", "СЕДУН О.О.")
SCAN_DPI = 150
SLIDE_COUNT = 3


def noisy_pdf(output: Path) -> None:
    """One page holding a large random-noise image, so any downsampling
    (the compressor's job) makes the file much smaller."""
    rng = random.Random(1)
    img = Image.frombytes("RGB", (1600, 1600), rng.randbytes(1600 * 1600 * 3))
    png = output.with_suffix(".noise.png")
    img.save(png)
    with pymupdf.open() as doc:
        page = doc.new_page()
        page.insert_image(page.rect, filename=str(png))
        doc.save(output)
    png.unlink()


def scan_pdf(output: Path) -> None:
    """A 'scanned' page: Ukrainian text rasterised into an image, so the only
    way to find it is OCR (like a real scan)."""
    font = next((f for f in CYRILLIC_FONTS if Path(f).exists()), None)
    if font is None:
        raise SystemExit("No Cyrillic TTF font found (install fonts-dejavu-core).")
    with pymupdf.open() as src:
        page = src.new_page()
        for i, line in enumerate(SCAN_LINES):
            page.insert_text(
                (72, 120 + i * 60),
                line,
                fontsize=28,
                fontname="cyr",
                fontfile=font,
            )
        pix = page.get_pixmap(dpi=SCAN_DPI)
    with pymupdf.open() as doc:
        out_page = doc.new_page(
            width=pix.width * 72 / SCAN_DPI, height=pix.height * 72 / SCAN_DPI
        )
        out_page.insert_image(out_page.rect, pixmap=pix)
        doc.save(output, deflate=True)


def slides_pdf(output: Path) -> None:
    """Three plain text pages, enough to check per-slide timing."""
    with pymupdf.open() as doc:
        for n in range(1, SLIDE_COUNT + 1):
            doc.new_page().insert_text((72, 100), f"Slide {n}", fontsize=40)
        doc.save(output)


def signature_png(output: Path) -> None:
    img = Image.new("RGBA", (200, 80))  # fully transparent
    ImageDraw.Draw(img).line(
        [(5, 60), (60, 10), (110, 70), (190, 20)], fill="blue", width=4
    )
    img.save(output)


if __name__ == "__main__":
    builders = {
        "noisy": noisy_pdf,
        "scan": scan_pdf,
        "signature": signature_png,
        "slides": slides_pdf,
    }
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=builders)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    builders[args.kind](args.output)
