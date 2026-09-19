import argparse
import glob
import os

import pymupdf as fitz
import pytesseract
from PIL import Image

OCR_DPI = 150
OCR_LANG = "ukr"


def _ocr_words(page, dpi=OCR_DPI):
    pix = page.get_pixmap(dpi=dpi)
    img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
    return pytesseract.image_to_data(img, lang=OCR_LANG, output_type=pytesseract.Output.DICT)


def find_name_box(page, name_parts, dpi=OCR_DPI):
    """Return (x0, y0, x1, y1) in PDF points around the first place on this
    page where the words of `name_parts` appear next to each other (matched
    by prefix, so Ukrainian case endings like СЕДУН / СЕДУНУ / СЕДУНА still
    match), or None if not found."""
    data = _ocr_words(page, dpi)
    scale = 72.0 / dpi
    lines = {}
    for i in range(len(data["text"])):
        w = data["text"][i].strip()
        if not w:
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        lines.setdefault(key, []).append(
            (w, data["left"][i], data["top"][i], data["width"][i], data["height"][i])
        )

    k = len(name_parts)
    for words in lines.values():
        words = sorted(words, key=lambda w: w[1])
        for start in range(len(words) - k + 1):
            window = words[start:start + k]
            if all(
                window[j][0].upper().startswith(name_parts[j])
                or name_parts[j].startswith(window[j][0].upper())
                for j in range(k)
            ):
                xs = [w[1] for w in window] + [w[1] + w[3] for w in window]
                ys = [w[2] for w in window] + [w[2] + w[4] for w in window]
                return (min(xs) * scale, min(ys) * scale, max(xs) * scale, max(ys) * scale)
    return None


def locate_signer(doc, signer_name):
    """Search pages from last to first. Returns (page_index, name_box)."""
    name_parts = [p.upper() for p in signer_name.split() if p.strip()]
    if not name_parts:
        raise ValueError("Ім'я підписанта не вказано.")
    for page_index in range(len(doc) - 1, -1, -1):
        box = find_name_box(doc[page_index], name_parts)
        if box:
            return page_index, box
    return None, None


def stamp(input_pdf, signature_png, signer_name, output_pdf,
          gap=10.0, height=48.0, shift=0.0):
    doc = fitz.open(input_pdf)
    page_index, name_box = locate_signer(doc, signer_name)
    if page_index is None:
        doc.close()
        raise RuntimeError(f"Ім'я «{signer_name}» не знайдено на жодній сторінці.")

    nx0, ny0, nx1, ny1 = name_box
    sig_img = Image.open(signature_png)
    ratio = sig_img.width / sig_img.height
    sig_h = height
    sig_w = sig_h * ratio

    x1 = nx0 - gap + shift
    x0 = x1 - sig_w
    y_center = (ny0 + ny1) / 2
    y0 = y_center - sig_h / 2
    y1 = y_center + sig_h / 2

    page = doc[page_index]
    page.insert_image(fitz.Rect(x0, y0, x1, y1), filename=signature_png, keep_proportion=True)
    doc.save(output_pdf)
    doc.close()
    print(f"[{os.path.basename(input_pdf)}] сторінка {page_index + 1}: підпис проставлено -> {output_pdf}")


def batch(input_dir, signature_png, signer_name, output_dir, **kwargs):
    os.makedirs(output_dir, exist_ok=True)
    files = sorted(glob.glob(os.path.join(input_dir, "*.pdf")))
    if not files:
        print(f"У папці {input_dir} не знайдено .pdf файлів.")
        return
    for f in files:
        out = os.path.join(output_dir, os.path.basename(f))
        try:
            stamp(f, signature_png, signer_name, out, **kwargs)
        except Exception as e:
            print(f"[{os.path.basename(f)}] ПОМИЛКА: {e}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("signature_png")
    ap.add_argument("signer_name")
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--gap", type=float, default=10.0)
    ap.add_argument("--height", type=float, default=48.0)
    ap.add_argument("--shift", type=float, default=0.0)
    args = ap.parse_args()

    kwargs = dict(gap=args.gap, height=args.height, shift=args.shift)
    if os.path.isdir(args.input):
        batch(args.input, args.signature_png, args.signer_name, args.output, **kwargs)
    else:
        stamp(args.input, args.signature_png, args.signer_name, args.output, **kwargs)
