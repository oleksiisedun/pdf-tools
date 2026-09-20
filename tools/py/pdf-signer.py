import argparse
from pathlib import Path

import pymupdf
import pytesseract
from PIL import Image

OCR_DPI = 150
OCR_LANG = "ukr"

Box = tuple[float, float, float, float]
Word = tuple[str, int, int, int, int]  # text, left, top, width, height (pixels)


def _ocr_words(page: pymupdf.Page, dpi: int = OCR_DPI) -> dict[str, list]:
    pix = page.get_pixmap(dpi=dpi)
    img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    return pytesseract.image_to_data(
        img, lang=OCR_LANG, output_type=pytesseract.Output.DICT
    )


def find_name_box(
    page: pymupdf.Page, name_parts: list[str], dpi: int = OCR_DPI
) -> Box | None:
    """Return (x0, y0, x1, y1) in PDF points around the first place on this
    page where the words of `name_parts` appear next to each other (matched
    by prefix, so Ukrainian case endings like СЕДУН / СЕДУНУ / СЕДУНА still
    match), or None if not found."""
    return match_name_box(_ocr_words(page, dpi), name_parts, dpi)


def match_name_box(
    data: dict[str, list], name_parts: list[str], dpi: int = OCR_DPI
) -> Box | None:
    """Pure matching half of `find_name_box`: `data` is pytesseract's
    image_to_data dict (pixel coordinates at `dpi`), `name_parts` upper-case."""
    scale = 72.0 / dpi
    lines: dict[tuple[int, int, int], list[Word]] = {}
    for i in range(len(data["text"])):
        w = data["text"][i].strip()
        if not w:
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        lines.setdefault(key, []).append(
            (w, data["left"][i], data["top"][i], data["width"][i], data["height"][i])
        )

    k = len(name_parts)
    for line_words in lines.values():
        words = sorted(line_words, key=lambda w: w[1])
        for start in range(len(words) - k + 1):
            window = words[start : start + k]
            if all(
                window[j][0].upper().startswith(name_parts[j])
                or name_parts[j].startswith(window[j][0].upper())
                for j in range(k)
            ):
                xs = [w[1] for w in window] + [w[1] + w[3] for w in window]
                ys = [w[2] for w in window] + [w[2] + w[4] for w in window]
                return (
                    min(xs) * scale,
                    min(ys) * scale,
                    max(xs) * scale,
                    max(ys) * scale,
                )
    return None


def locate_signer(doc: pymupdf.Document, signer_name: str) -> tuple[int, Box] | None:
    """Search pages from last to first. Returns (page_index, name_box), or
    None if the name appears on no page."""
    name_parts = [p.upper() for p in signer_name.split() if p.strip()]
    if not name_parts:
        raise ValueError("Ім'я підписанта не вказано.")
    for page_index in range(len(doc) - 1, -1, -1):
        box = find_name_box(doc[page_index], name_parts)
        if box:
            return page_index, box
    return None


def signature_rect(
    name_box: Box,
    image_size: tuple[int, int],
    *,
    gap: float,
    height: float,
    shift: float,
) -> Box:
    """Rect (PDF points) for the signature: `height` tall, width following the
    image's aspect ratio, right edge `gap` (minus `shift`) left of the name box,
    vertically centered on it."""
    nx0, ny0, _, ny1 = name_box
    img_w, img_h = image_size
    x1 = nx0 - gap + shift
    x0 = x1 - height * img_w / img_h
    y_center = (ny0 + ny1) / 2
    return (x0, y_center - height / 2, x1, y_center + height / 2)


def stamp(
    input_pdf: Path,
    signature_png: Path,
    signer_name: str,
    output_pdf: Path,
    *,
    gap: float,
    height: float,
    shift: float,
) -> None:
    with pymupdf.open(input_pdf) as doc:
        located = locate_signer(doc, signer_name)
        if located is None:
            raise RuntimeError(f"Ім'я «{signer_name}» не знайдено на жодній сторінці.")
        page_index, name_box = located

        with Image.open(signature_png) as sig_img:
            rect = signature_rect(
                name_box, sig_img.size, gap=gap, height=height, shift=shift
            )

        doc[page_index].insert_image(
            pymupdf.Rect(*rect),
            filename=str(signature_png),
            keep_proportion=True,
        )
        doc.save(output_pdf)
    print(
        f"[{input_pdf.name}] сторінка {page_index + 1}: "
        f"підпис проставлено -> {output_pdf}"
    )


def batch(
    input_dir: Path,
    signature_png: Path,
    signer_name: str,
    output_dir: Path,
    **placement: float,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    files = sorted(input_dir.glob("*.pdf"))
    if not files:
        print(f"У папці {input_dir} не знайдено .pdf файлів.")
        return
    for f in files:
        try:
            stamp(f, signature_png, signer_name, output_dir / f.name, **placement)
        except (RuntimeError, ValueError, OSError) as e:
            print(f"[{f.name}] ПОМИЛКА: {e}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("signature_png", type=Path)
    ap.add_argument("signer_name")
    ap.add_argument("--input", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    # No defaults: tools/pdf-signer.sh owns them (DEFAULT_GAP etc.).
    ap.add_argument("--gap", required=True, type=float)
    ap.add_argument("--height", required=True, type=float)
    ap.add_argument("--shift", required=True, type=float)
    args = ap.parse_args()

    placement = {"gap": args.gap, "height": args.height, "shift": args.shift}
    if args.input.is_dir():
        batch(
            args.input, args.signature_png, args.signer_name, args.output, **placement
        )
    else:
        stamp(
            args.input, args.signature_png, args.signer_name, args.output, **placement
        )
