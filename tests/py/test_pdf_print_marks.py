import importlib.util
import random
from pathlib import Path

import pytest

# The file name has a hyphen (it mirrors tools/pdf-print-marks.sh), so it can't
# be imported with a plain `import`.
_PATH = Path(__file__).parents[2] / "tools" / "py" / "pdf-print-marks.py"
_spec = importlib.util.spec_from_file_location("pdf_print_marks", _PATH)
assert _spec is not None and _spec.loader is not None
marks = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(marks)


def ocr_line(*words: str, height: int = 40) -> dict[str, list]:
    """pytesseract-style dict with the words on one line, 100 px apart."""
    n = len(words)
    return {
        "text": list(words),
        "left": [100 * i for i in range(n)],
        "top": [50] * n,
        "width": [90] * n,
        "height": [height] * n,
        "block_num": [1] * n,
        "par_num": [1] * n,
        "line_num": [1] * n,
    }


class TestLooksLikeSurname:
    @pytest.mark.parametrize(
        ("word", "next_word"),
        [
            ("СЕДУН", "О.О."),
            ("СЕДУН,", None),  # surname suffix, trailing OCR punctuation
            ("ІВАНЕНКО", None),
            ("ПЕТРОВ", "І.І."),
            ("КОВАЛЬ", "І."),  # no known suffix, initials follow
        ],
    )
    def test_accepts(self, word, next_word):
        assert marks.looks_like_surname(word, next_word)

    @pytest.mark.parametrize(
        "word", ["РАПОРТ", "ККУ", "КУпАП", "ПЗК-НШ", "ХАРТІЯ", "Седун", "АБС1"]
    )
    def test_rejects_non_surnames(self, word):
        assert not marks.looks_like_surname(word, None)

    def test_stopword_rejected_even_before_initials(self):
        assert not marks.looks_like_surname("РАПОРТ", "О.")

    def test_no_initials_and_no_suffix_is_rejected(self):
        assert not marks.looks_like_surname("КОВАЛЬ", "служить")


class TestFindSurnameBoxes:
    def test_box_is_converted_from_pixels_to_points(self):
        data = ocr_line("Капітан", "СЕДУН", "О.О.")
        # At 144 dpi one pixel is 0.5 pt; СЕДУН is at left=100, top=50, 90x40 px.
        assert marks.find_surname_boxes(data, dpi=144) == [(50, 25, 95, 45)]

    def test_skips_blank_tokens_and_false_positives(self):
        data = ocr_line("РАПОРТ", " ", "ККУ", "КУпАП")
        assert marks.find_surname_boxes(data) == []


class TestTargetCount:
    @pytest.mark.parametrize(
        ("total", "intensity", "expected"),
        [(20, 1, 2), (20, 10, 20), (3, 1, 1), (3, 10, 3), (1, 5, 1), (0, 5, 0)],
    )
    def test_scales_with_intensity(self, total, intensity, expected):
        assert marks.target_count(total, intensity) == expected

    def test_intensity_one_with_many_surnames_is_at_least_one(self):
        assert marks.target_count(4, 1) == 1


class TestMarkRect:
    def test_sits_right_of_word_and_is_square(self):
        x0, y0, x1, y1 = marks.mark_rect((100, 50, 150, 60))
        assert x0 > 150
        assert y0 < 60 < y1
        assert x1 - x0 == pytest.approx(y1 - y0)


def test_annotation_flags_are_print_plus_noview():
    assert marks.ANNOT_FLAGS == 4 | 32


def test_hidden_annotation_flag_is_hidden_only():
    assert marks.HIDDEN_ANNOT_FLAGS == 2


def test_read_message_strips_whitespace(tmp_path):
    f = tmp_path / "m.txt"
    f.write_text("  привіт\n\n", encoding="utf-8")
    assert marks.read_message(f) == "привіт"


def test_read_message_rejects_blank_file(tmp_path):
    f = tmp_path / "m.txt"
    f.write_text(" \n", encoding="utf-8")
    with pytest.raises(ValueError):
        marks.read_message(f)


def test_add_hidden_message_stores_text_without_changing_the_render():
    import pymupdf

    with pymupdf.open() as doc:
        doc.new_page()
        page = doc[0]  # annotations die with their page object
        before = page.get_pixmap().samples
        marks.add_hidden_message(doc, "секрет")
        annots = list(page.annots())
        assert len(annots) == 1
        assert annots[0].flags == marks.HIDDEN_ANNOT_FLAGS
        assert annots[0].info["content"] == "секрет"
        assert page.get_pixmap().samples == before


def test_seeded_choice_is_deterministic():
    picks = [random.Random(7).choice(marks.MARKS) for _ in range(3)]
    assert len(set(picks)) == 1


def test_group_lines_skips_blanks_and_orders_left_to_right():
    from ocr_common import group_lines

    data = ocr_line("B", " ", "A")
    data["left"] = [200, 100, 0]
    assert group_lines(data) == [[2, 0]]
