import pymupdf
import pytesseract
from PIL import Image

OCR_DPI = 150
OCR_LANG = "ukr"


def ocr_words(page: pymupdf.Page, dpi: int = OCR_DPI) -> dict[str, list]:
    pix = page.get_pixmap(dpi=dpi)
    img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    return pytesseract.image_to_data(
        img, lang=OCR_LANG, output_type=pytesseract.Output.DICT
    )
