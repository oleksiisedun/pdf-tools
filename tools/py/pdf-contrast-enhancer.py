import sys
import tempfile
from pathlib import Path

import img2pdf
from pdf2image import convert_from_path
from PIL import ImageEnhance

RENDER_DPI = 300
CONTRAST = 2.5
SHARPNESS = 1.5
JPEG_QUALITY = 85


def main(input_pdf: str, output_pdf: str) -> None:
    """Render every page, boost contrast/sharpness, and reassemble into
    output_pdf. Reports progress as "PROGRESS:i/total" lines on stdout,
    which the calling bash script parses to draw its progress bar."""
    images = convert_from_path(input_pdf, dpi=RENDER_DPI)
    total = len(images)
    print(f"PROGRESS:0/{total}", flush=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        enhanced_paths: list[str] = []
        for i, img in enumerate(images):
            img = ImageEnhance.Contrast(img).enhance(CONTRAST)
            img = ImageEnhance.Sharpness(img).enhance(SHARPNESS)
            path = Path(tmpdir) / f"page_{i}.jpg"
            img.save(path, "JPEG", quality=JPEG_QUALITY)
            enhanced_paths.append(str(path))
            print(f"PROGRESS:{i + 1}/{total}", flush=True)

        pdf_bytes = img2pdf.convert(enhanced_paths)
        if pdf_bytes is None:  # only returned when an output stream is given
            raise RuntimeError("img2pdf produced no output")
        Path(output_pdf).write_bytes(pdf_bytes)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
