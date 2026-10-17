import argparse
import random
import re
import shutil
from pathlib import Path

import pymupdf
from ocr_common import OCR_DPI, ocr_words

Box = tuple[float, float, float, float]

MARKS = (".", ",", ";", '"')
MIN_SURNAME_LETTERS = 4
CYRILLIC_UPPER = "А-ЯІЇЄҐ"
INITIALS_RE = re.compile(rf"^[{CYRILLIC_UPPER}]\.?([{CYRILLIC_UPPER}]\.?)?$")
SURNAME_RE = re.compile(rf"^[{CYRILLIC_UPPER}]+$")
# ALL-CAPS words that are never surnames even if they pass the other checks.
STOPWORDS = frozenset({"РАПОРТ", "ХАРТІЯ", "ПРОТОКОЛ", "ВИСНОВОК", "ПОСТАНОВА"})
SURNAME_SUFFIXES = (
    "ЕНКО", "ЧУК", "ЮК", "СЬКИЙ", "ЦЬКИЙ", "СЬКА", "ЦЬКА",
    "ОВ", "ЕВ", "ОВА", "ЕВА", "ІН", "ІНА", "УН", "ИН", "ИНА",
)  # fmt: skip
# Where the mark sits relative to the word it follows, as fractions of the
# word's height: font size, left padding and how far the box starts above the
# word's top edge (so the glyph lands on the word's baseline).
FONT_SIZE_RATIO = 1.4
LEFT_PAD_RATIO = 0.1
TOP_OFFSET_RATIO = 0.15
# PDF 32000-1 table 165: Print (bit 3) + NoView (bit 6).
ANNOT_FLAGS = pymupdf.PDF_ANNOT_IS_PRINT | pymupdf.PDF_ANNOT_IS_NO_VIEW


def strip_punctuation(text: str) -> str:
    return text.strip(".,;:!?\"'«»()[]")


def is_surname_candidate(text: str) -> bool:
    word = strip_punctuation(text)
    return (
        len(word) >= MIN_SURNAME_LETTERS
        and SURNAME_RE.match(word) is not None
        and word not in STOPWORDS
    )


def looks_like_surname(word: str, next_word: str | None) -> bool:
    """A candidate counts as a surname if initials follow it or it ends like one."""
    if not is_surname_candidate(word):
        return False
    if next_word is not None and INITIALS_RE.match(strip_punctuation(next_word)):
        return True
    return strip_punctuation(word).endswith(SURNAME_SUFFIXES)


def find_surname_boxes(data: dict[str, list], dpi: int = OCR_DPI) -> list[Box]:
    """Boxes (PDF points) of the surnames in pytesseract's image_to_data dict."""
    scale = 72.0 / dpi
    lines: dict[tuple[int, int, int], list[int]] = {}
    for i, text in enumerate(data["text"]):
        if text.strip():
            key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
            lines.setdefault(key, []).append(i)

    boxes = []
    for indices in lines.values():
        indices.sort(key=lambda i: data["left"][i])
        for pos, i in enumerate(indices):
            nxt = data["text"][indices[pos + 1]] if pos + 1 < len(indices) else None
            if looks_like_surname(data["text"][i], nxt):
                left, top = data["left"][i], data["top"][i]
                boxes.append(
                    (
                        left * scale,
                        top * scale,
                        (left + data["width"][i]) * scale,
                        (top + data["height"][i]) * scale,
                    )
                )
    return boxes


def target_count(total: int, intensity: int) -> int:
    """1 -> a single surname, 10 -> all of them (0 when there are none)."""
    if total == 0:
        return 0
    return min(total, max(1, round(total * intensity / 10)))


def mark_rect(word_box: Box) -> Box:
    """Annotation rect for a one-character mark right after `word_box`."""
    x0, y0, x1, y1 = word_box
    height = y1 - y0
    size = height * FONT_SIZE_RATIO
    left = x1 + height * LEFT_PAD_RATIO
    top = y0 - height * TOP_OFFSET_RATIO
    return (left, top, left + size, top + size)


def add_marks(
    input_pdf: Path, output_pdf: Path, intensity: int, seed: int | None
) -> int:
    """Copy `input_pdf` and append print-only marks as an incremental update,
    so the original objects (page content, image streams) stay byte-identical."""
    shutil.copyfile(input_pdf, output_pdf)
    rng = random.Random(seed)
    with pymupdf.open(output_pdf) as doc:
        found = [
            (page_index, box)
            for page_index, page in enumerate(doc)
            for box in find_surname_boxes(ocr_words(page))
        ]
        if not found:
            raise RuntimeError("Прізвищ, написаних ВЕЛИКИМИ літерами, не знайдено.")
        chosen = rng.sample(found, target_count(len(found), intensity))
        for page_index, box in chosen:
            rect = pymupdf.Rect(*mark_rect(box))
            annot = doc[page_index].add_freetext_annot(
                rect,
                rng.choice(MARKS),
                fontsize=rect.height,
                text_color=(0, 0, 0),
            )
            annot.set_border(width=0)
            annot.set_flags(ANNOT_FLAGS)
            annot.update()
        doc.saveIncr()
    return len(chosen)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    # No default: tools/pdf-print-marks.sh owns it (DEFAULT_INTENSITY).
    ap.add_argument("--intensity", required=True, type=int, choices=range(1, 11))
    ap.add_argument("--seed", type=int)
    args = ap.parse_args()

    n = add_marks(args.input, args.output, args.intensity, args.seed)
    print(f"[{args.input.name}] позначок додано: {n} -> {args.output}")
