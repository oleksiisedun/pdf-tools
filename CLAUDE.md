## What this is

A collection of small interactive bash scripts for common PDF tasks (A5→A4 imposition, Ghostscript compression, contrast/sharpness enhancement, PDF-to-slideshow-video conversion). No build system, no package manager, no automated test suite — everything is plain bash plus a small embedded Python script for the contrast tool.

## Running / verifying changes

There's no test suite. Verify a change by actually running the affected tool end-to-end:

```bash
./pdf-tools.sh                 # interactive menu
./pdf-tools.sh compressor       # jump straight to a tool by key
./pdf-tools.sh 1                 # or by menu number
./scripts/pdf-compressor.sh      # run a tool standalone, bypassing the menu
```

A quick syntax check without executing anything: `bash -n scripts/<file>.sh`.

Each tool declares its own external dependency and checks for it at startup (`require_bin` in `pdf-a5-print.sh`/`pdf-compressor.sh`/`pdf-to-video.sh`; a manual apt-check block in `pdf-contrast-enhancer.sh`). Install the relevant package before testing a tool:

- `pdf-a5-print.sh` → `texlive-extra-utils` (provides `pdfjam`)
- `pdf-compressor.sh` → `ghostscript` (`gs`)
- `pdf-contrast-enhancer.sh` → `python3`, `python3-venv`, `poppler-utils` (auto-installed on first run if missing)
- `pdf-to-video.sh` → `poppler-utils` (`pdftoppm`, `pdfinfo`), `ffmpeg`

## Architecture

`pdf-tools.sh` is a thin dispatcher; each tool script sources `scripts/common.sh` for shared interactive helpers, then shells out to its own external dependency to do the real work.

```mermaid
graph TD
  Menu["pdf-tools.sh\n(entry point / dispatcher)"]

  subgraph Scripts["scripts/"]
    Common["common.sh\n(shared helpers)"]
    A5["pdf-a5-print.sh"]
    Compressor["pdf-compressor.sh"]
    Contrast["pdf-contrast-enhancer.sh"]
    ToVideo["pdf-to-video.sh"]
  end

  Menu --> A5
  Menu --> Compressor
  Menu --> Contrast
  Menu --> ToVideo

  A5 --> Common
  Compressor --> Common
  Contrast --> Common
  ToVideo --> Common

  A5 --> Pdfjam[("pdfjam / texlive-extra-utils")]
  Compressor --> Ghostscript[("Ghostscript")]
  Contrast --> Venv[("Python venv\npdf2image + pillow + img2pdf")]
  ToVideo --> Pdftoppm[("pdftoppm / poppler-utils")]
  ToVideo --> Ffmpeg[("ffmpeg")]
```

### Dispatcher pattern (`pdf-tools.sh`)

Tools are registered as three parallel arrays — `TOOL_KEYS`, `TOOL_LABELS`, `TOOL_SCRIPTS` — indexed together. `resolve_tool()` maps a menu number or key string to an array index; `run_tool()` execs the script at that index. **To add a new tool, append one entry to each of the three arrays** and add the corresponding script under `scripts/`; no other dispatcher code needs to change.

### Shared helpers (`scripts/common.sh`)

Sourced (never executed) by every tool script. Provides:

- `ok`/`warn`/`err` — colored status messages, written to **stderr**. This matters: `prompt_input_file` and `prompt_output_path` return their result via `echo` on stdout captured through command substitution (`$(...)`), so any status text written to stdout would corrupt the returned path.
- `clean_path` — normalizes a drag-and-dropped path (tilde expansion, strips surrounding quotes, unescapes backslash-escaped spaces).
- `require_bin` — the "single binary must exist or bail with an apt install hint" dependency check. Only fits the single-binary case (`pdfjam`, `gs`); the contrast-enhancer's multi-package + venv bootstrap is different in kind and stays inline in its own script rather than being generalized here.
- `prompt_input_file` / `prompt_output_path` — the shared file-prompt loops (validate-exists, default-on-empty, overwrite-confirmation) that back every tool's I/O prompts. `prompt_output_path` takes an optional `[extension]` argument (default `pdf`) so non-PDF outputs like `pdf-to-video.sh`'s `.mp4` can reuse the same loop instead of duplicating it.
- `draw_progress` — renders an in-place ASCII progress bar (`\r` + fixed width). Callers parse tool-specific progress markers out of a subprocess's output stream and feed a current/total count to this function (see below). Takes an optional `[label]` argument (default `page`) so non-page units like `pdf-to-video.sh`'s `sec` can reuse it.
- `dump_log_and_die` — prints `"<label> failed. Full log:"`, cats the tool's tempfile logfile, removes it, and exits 1. Every tool calls this from its failure branch instead of repeating the cat/rm/exit sequence inline.
- `report_size_comparison` — prints the `"Done! Output saved to: ..."` success message plus input/output file sizes (via `du -sh`). Used by tools that transform a PDF in place (compressor, contrast-enhancer); `pdf-a5-print.sh` prints its own "Done!" line directly since combining two inputs into one output has no single size comparison to report.

### Per-tool scripts

Each tool script follows the same shape: dependency check → prompt for input file → prompt for tool-specific options → prompt for output path → run the external tool into a temp logfile, calling `dump_log_and_die` on failure and `report_size_comparison` (where applicable) on success.

- **`pdf-a5-print.sh`** — thinnest tool; single `pdfjam` invocation, no progress bar.
- **`pdf-compressor.sh`** — pipes Ghostscript's own stderr output through a `while read` loop, regex-matching `Processing pages 1 through N` and `Page N` lines to drive `draw_progress`. Exit status is captured via `PIPESTATUS[0]` since the real command is the left side of a pipe.
- **`pdf-contrast-enhancer.sh`** — the most involved tool. It bootstraps a persistent venv at `~/.pdf-contrast-enhancer-venv` (created once, reused across runs), writes an embedded Python script to a tempfile via heredoc, and runs it through the venv's Python. The Python script prints `PROGRESS:i/total` lines to stdout, which the bash side parses the same way as the compressor's Ghostscript output. Same `PIPESTATUS[0]` pattern for exit-code capture.
- **`pdf-to-video.sh`** — renders every PDF page to a PNG with `pdftoppm`, builds an ffmpeg concat-demuxer list assigning each image a fixed duration (uniform seconds-per-slide, prompted once), then encodes with `ffmpeg` into a 1920x1080 letterboxed H.264/yuv420p MP4 for broad TV/USB playback. Parses ffmpeg's `-progress pipe:1` `out_time_ms=` output to drive `draw_progress` in seconds rather than pages. Uses its own `mktemp -d` scratch directory cleaned up via `trap ... EXIT` (rendered PNGs and the concat list don't fit the single-logfile pattern the other tools use). Prints a custom "Done!" summary instead of `report_size_comparison`, since comparing PDF size to video size isn't meaningful.

### Adding a new tool

1. Create `scripts/pdf-<name>.sh`, sourcing `common.sh` and following the dependency-check → input → options → output → run shape above.
2. Register it in `pdf-tools.sh`'s three parallel arrays.
3. Update `.gitignore` if the tool produces a default output filename that should be excluded (see existing `*_compressed.pdf`, `*_contrast.pdf`, `output_A4_landscape.pdf` entries).
