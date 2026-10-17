"""Tesseract OCR helpers shared by the signer and print-marks tools."""

import pymupdf
import pytesseract
from PIL import Image

OCR_DPI = 150
OCR_LANG = "ukr"

Box = tuple[float, float, float, float]  # x0, y0, x1, y1 in PDF points


def group_lines(data: dict[str, list]) -> list[list[int]]:
    """Indices of the non-blank words in pytesseract's image_to_data dict,
    grouped per text line and ordered left to right within each line."""
    lines: dict[tuple[int, int, int], list[int]] = {}
    for i, text in enumerate(data["text"]):
        if text.strip():
            key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
            lines.setdefault(key, []).append(i)
    for indices in lines.values():
        indices.sort(key=lambda i: data["left"][i])
    return list(lines.values())


def ocr_words(page: pymupdf.Page, dpi: int = OCR_DPI) -> dict[str, list]:
    pix = page.get_pixmap(dpi=dpi)
    img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    return pytesseract.image_to_data(
        img, lang=OCR_LANG, output_type=pytesseract.Output.DICT
    )
