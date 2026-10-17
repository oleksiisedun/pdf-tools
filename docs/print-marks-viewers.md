# pdf-print-marks: viewer and printer results

The tool adds each mark as a FreeText annotation with flags `Print` + `NoView`
(`/F 36`). Per the PDF spec NoView hides it on screen while Print still prints it.
The scan itself is untouched: the output is the input plus an incremental update.

## Automated checks (pymupdf)

| Check | Result |
| --- | --- |
| Every added annotation has `/F` = 36 | pass |
| Output starts with the input's exact bytes (image streams byte-identical) | pass |
| Screen render of output == screen render of input | pass |
| Render with NoView cleared shows the marks on the baseline after the surname | pass |

## Manual checks (real printer)

Check on screen at several zoom levels (no mark visible), then print.

| Viewer | Invisible on screen | Printed on paper | Notes |
| --- | --- | --- | --- |
| Acrobat Reader | | | not tested |
| Chrome (Linux) | yes | yes | Tested 2026-10-17 |
| Firefox (pdf.js) | | | not tested |
| macOS Preview | | | not tested |
| Xreader (Linux) | yes | yes | Tested 2026-10-17 |
| Okular | | | not tested |

Tip: "Print to PDF" first and open the result at 400% to see which marks survived.
