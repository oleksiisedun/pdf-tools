pdf-compressor
==============

A bash script that compresses a PDF using Ghostscript.

Setup
-----

Make the script executable before running it for the first time:

    cd compressor
    chmod +x ./pdf-compressor.sh

Dependency
----------

Requires `ghostscript`:

    sudo apt install ghostscript

Usage
-----

    cd compressor
    ./pdf-compressor.sh

The script will interactively prompt you for:

1. **Input PDF** — path to the file you want to compress
2. **Compression level** — choose one of three quality presets
3. **Output file name** — defaults to `<original-name>_compressed.pdf`

File paths can be typed manually or dragged and dropped from a file manager. The script handles `~` expansion, quoted paths, and backslash-escaped spaces.

If the output file already exists, you will be prompted to overwrite it or choose a different name.

Compression levels
------------------

| # | Preset     | DPI | Description                  |
|---|------------|-----|------------------------------|
| 1 | `screen`   |  72 | Smallest file, lowest quality |
| 2 | `ebook`    | 150 | Moderate quality *(default)* |
| 3 | `prepress` | 300 | Highest quality, larger file |

Note: compression results vary depending on the source material — some PDFs may not shrink significantly.