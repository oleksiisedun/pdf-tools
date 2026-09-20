import importlib.util
from pathlib import Path

import pytest

# The file name has a hyphen (it mirrors tools/pdf-signer.sh), so it can't be
# imported with a plain `import`.
_SIGNER = Path(__file__).parents[2] / "tools" / "py" / "pdf-signer.py"
_spec = importlib.util.spec_from_file_location("pdf_signer", _SIGNER)
assert _spec is not None and _spec.loader is not None
signer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(signer)

# One OCR word: (text, left, top, width, height) in pixels, plus the
# (block, paragraph, line) it sits in.
OcrWord = tuple[str, int, int, int, int]


def ocr_data(*lines: list[OcrWord]) -> dict[str, list]:
    """Build the dict pytesseract.image_to_data returns, one line per argument."""
    data: dict[str, list] = {k: [] for k in ("text", "left", "top", "width", "height")}
    data.update(block_num=[], par_num=[], line_num=[])
    for line_num, words in enumerate(lines, start=1):
        for text, left, top, width, height in words:
            data["text"].append(text)
            data["left"].append(left)
            data["top"].append(top)
            data["width"].append(width)
            data["height"].append(height)
            data["block_num"].append(1)
            data["par_num"].append(1)
            data["line_num"].append(line_num)
    return data


class TestMatchNameBox:
    def test_single_word_box_is_converted_from_pixels_to_points(self):
        data = ocr_data([("СЕДУН", 300, 100, 200, 40)])
        # At 144 dpi one pixel is 0.5 pt.
        assert signer.match_name_box(data, ["СЕДУН"], dpi=144) == (150, 50, 250, 70)

    @pytest.mark.parametrize("ocr_word", ["СЕДУН", "СЕДУНУ", "СЕДУНА", "седун"])
    def test_ocr_word_may_extend_the_name_by_a_case_ending(self, ocr_word):
        data = ocr_data([(ocr_word, 0, 0, 10, 10)])
        assert signer.match_name_box(data, ["СЕДУН"], dpi=72) is not None

    def test_ocr_word_may_be_a_truncation_of_the_name(self):
        data = ocr_data([("СЕД", 0, 0, 10, 10)])
        assert signer.match_name_box(data, ["СЕДУН"], dpi=72) is not None

    def test_unrelated_word_does_not_match(self):
        data = ocr_data([("ІВАНЕНКО", 0, 0, 10, 10)])
        assert signer.match_name_box(data, ["СЕДУН"], dpi=72) is None

    def test_multi_word_name_yields_the_union_box(self):
        data = ocr_data(
            [
                ("Підпис:", 0, 5, 50, 10),
                ("СЕДУН", 100, 0, 40, 20),
                ("О.В.", 150, 8, 30, 12),
            ]
        )
        assert signer.match_name_box(data, ["СЕДУН", "О.В."], dpi=72) == (
            100,
            0,
            180,
            20,
        )

    def test_words_are_ordered_by_position_not_by_ocr_order(self):
        data = ocr_data([("О.В.", 150, 0, 30, 10), ("СЕДУН", 100, 0, 40, 10)])
        assert signer.match_name_box(data, ["СЕДУН", "О.В."], dpi=72) == (
            100,
            0,
            180,
            10,
        )

    def test_name_parts_in_the_wrong_order_do_not_match(self):
        data = ocr_data([("О.В.", 100, 0, 30, 10), ("СЕДУН", 150, 0, 40, 10)])
        assert signer.match_name_box(data, ["СЕДУН", "О.В."], dpi=72) is None

    def test_a_word_between_the_name_parts_breaks_the_match(self):
        data = ocr_data(
            [("СЕДУН", 0, 0, 40, 10), ("і", 50, 0, 5, 10), ("О.В.", 60, 0, 30, 10)]
        )
        assert signer.match_name_box(data, ["СЕДУН", "О.В."], dpi=72) is None

    def test_name_split_across_lines_does_not_match(self):
        data = ocr_data([("СЕДУН", 0, 0, 40, 10)], [("О.В.", 0, 20, 30, 10)])
        assert signer.match_name_box(data, ["СЕДУН", "О.В."], dpi=72) is None

    def test_blank_ocr_tokens_are_ignored(self):
        data = ocr_data(
            [
                ("", 0, 0, 0, 0),
                ("СЕДУН", 10, 0, 40, 10),
                ("  ", 50, 0, 0, 0),
                ("О.В.", 60, 0, 30, 10),
            ]
        )
        assert signer.match_name_box(data, ["СЕДУН", "О.В."], dpi=72) == (10, 0, 90, 10)

    def test_name_longer_than_the_line_does_not_match(self):
        data = ocr_data([("СЕДУН", 0, 0, 40, 10)])
        assert signer.match_name_box(data, ["СЕДУН", "О.В."], dpi=72) is None

    def test_first_occurrence_wins(self):
        data = ocr_data([("СЕДУН", 0, 0, 10, 10)], [("СЕДУН", 0, 500, 10, 10)])
        assert signer.match_name_box(data, ["СЕДУН"], dpi=72) == (0, 0, 10, 10)

    def test_empty_ocr_result_returns_none(self):
        assert signer.match_name_box(ocr_data(), ["СЕДУН"], dpi=72) is None


class TestSignatureRect:
    def test_signature_sits_left_of_the_name_and_is_vertically_centered(self):
        rect = signer.signature_rect(
            (200, 100, 300, 120), (200, 100), gap=10, height=40, shift=0
        )
        # Aspect 2:1 at height 40 -> 80 wide; right edge 10 left of the name.
        assert rect == (110, 90, 190, 130)

    def test_width_follows_the_image_aspect_ratio(self):
        wide = signer.signature_rect(
            (200, 0, 300, 10), (300, 100), gap=0, height=30, shift=0
        )
        tall = signer.signature_rect(
            (200, 0, 300, 10), (100, 300), gap=0, height=30, shift=0
        )
        assert wide[2] - wide[0] == pytest.approx(90)
        assert tall[2] - tall[0] == pytest.approx(10)

    def test_height_is_exactly_the_requested_height(self):
        rect = signer.signature_rect(
            (200, 0, 300, 10), (123, 77), gap=5, height=33, shift=0
        )
        assert rect[3] - rect[1] == pytest.approx(33)

    def test_positive_shift_moves_the_signature_right_without_resizing(self):
        base = signer.signature_rect(
            (200, 0, 300, 10), (100, 100), gap=10, height=20, shift=0
        )
        shifted = signer.signature_rect(
            (200, 0, 300, 10), (100, 100), gap=10, height=20, shift=7
        )
        assert shifted[0] - base[0] == pytest.approx(7)
        assert shifted[2] - base[2] == pytest.approx(7)
        assert shifted[1:4:2] == base[1:4:2]

    def test_larger_gap_moves_the_signature_left(self):
        near = signer.signature_rect(
            (200, 0, 300, 10), (100, 100), gap=5, height=20, shift=0
        )
        far = signer.signature_rect(
            (200, 0, 300, 10), (100, 100), gap=15, height=20, shift=0
        )
        assert near[2] - far[2] == pytest.approx(10)


class TestLocateSigner:
    @staticmethod
    def _stub_pages(monkeypatch, hits: dict[int, tuple[float, float, float, float]]):
        searched: list[int] = []

        def fake_find(page: int, name_parts: list[str]):
            searched.append(page)
            return hits.get(page)

        monkeypatch.setattr(signer, "find_name_box", fake_find)
        return searched

    def test_searches_last_page_first_and_stops_at_the_first_hit(self, monkeypatch):
        box = (1.0, 2.0, 3.0, 4.0)
        searched = self._stub_pages(monkeypatch, {0: (9, 9, 9, 9), 2: box})
        assert signer.locate_signer([0, 1, 2, 3], "Седун") == (2, box)
        assert searched == [3, 2]

    def test_returns_none_when_no_page_has_the_name(self, monkeypatch):
        searched = self._stub_pages(monkeypatch, {})
        assert signer.locate_signer([0, 1], "Седун") is None
        assert searched == [1, 0]

    def test_name_is_split_on_whitespace_and_uppercased(self, monkeypatch):
        seen: list[list[str]] = []
        monkeypatch.setattr(
            signer, "find_name_box", lambda page, parts: seen.append(parts)
        )
        signer.locate_signer([0], "  Седун   О.в. ")
        assert seen == [["СЕДУН", "О.В."]]

    @pytest.mark.parametrize("name", ["", "   "])
    def test_blank_name_is_rejected(self, name):
        with pytest.raises(ValueError):
            signer.locate_signer([0], name)


class TestBatch:
    PLACEMENT = {"gap": 1.0, "height": 2.0, "shift": 3.0}

    def test_reports_when_the_folder_has_no_pdfs(self, tmp_path, capsys, monkeypatch):
        monkeypatch.setattr(signer, "stamp", pytest.fail)
        signer.batch(
            tmp_path, tmp_path / "s.png", "Седун", tmp_path / "out", **self.PLACEMENT
        )
        assert "не знайдено .pdf" in capsys.readouterr().out

    def test_continues_past_a_failing_file_and_reports_it(
        self, tmp_path, capsys, monkeypatch
    ):
        for name in ("b.pdf", "a.pdf", "c.pdf", "notes.txt"):
            (tmp_path / name).touch()
        stamped: list[str] = []

        def fake_stamp(input_pdf, signature_png, signer_name, output_pdf, **placement):
            if input_pdf.name == "b.pdf":
                raise RuntimeError("не знайдено")
            stamped.append(input_pdf.name)
            assert output_pdf == tmp_path / "out" / input_pdf.name
            assert placement == self.PLACEMENT

        monkeypatch.setattr(signer, "stamp", fake_stamp)
        signer.batch(
            tmp_path, tmp_path / "s.png", "Седун", tmp_path / "out", **self.PLACEMENT
        )

        assert stamped == ["a.pdf", "c.pdf"]
        assert "[b.pdf] ПОМИЛКА: не знайдено" in capsys.readouterr().out
