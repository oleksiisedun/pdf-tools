pdf-contrast-enhancer
=====================

A bash script that increases the contrast and sharpness of a PDF.

Setup
-----

Make the script executable before running it for the first time:

    cd contrast-enhancer
    chmod +x ./pdf-contrast-enhancer.sh

Dependencies
------------

Requires `python3`, `python3-venv`, and `poppler-utils`:

    sudo apt install python3 python3-venv poppler-utils

Missing packages are detected and installed automatically on first run.

The script also creates a Python virtual environment at `~/.pdf-contrast-enhancer-venv` and installs the required Python packages (`pdf2image`, `pillow`, `img2pdf`) on first run.

Usage
-----

    cd contrast-enhancer
    ./pdf-contrast-enhancer.sh

The script will interactively prompt you for:

1. **Input PDF** — path to the file you want to enhance
2. **Output file name** — defaults to `<original-name>_contrast.pdf`

File paths can be typed manually or dragged and dropped from a file manager. The script handles `~` expansion, quoted paths, and backslash-escaped spaces.

If the output file already exists, you will be prompted to overwrite it or choose a different name.

Processing
----------

Each page is rendered at 300 DPI, enhanced, and saved as JPEG (quality 85) before being reassembled into a PDF:

| Enhancement | Factor |
|-------------|--------|
| Contrast    | 2.5×   |
| Sharpness   | 1.5×   |

Output file size will be comparable to the original.
