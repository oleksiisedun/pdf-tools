# pdf-a5-print

A bash script that combines two A5 PDFs side by side onto a single A4 landscape page.

## Setup

Make the script executable before running it for the first time:

```bash
cd a5-print
chmod +x ./pdf-a5-print.sh
```

## Dependency

Requires `pdfjam` from the `texlive-extra-utils` package:

```bash
sudo apt install texlive-extra-utils
```

## Usage

```bash
cd a5-print
./pdf-a5-print.sh
```

The script will interactively prompt you for:

1. **First A5 PDF** — path to the first input file
2. **Second A5 PDF** — path to the second input file (press Enter to reuse the first file)
3. **Output file name** — defaults to `output_A4_landscape.pdf`

File paths can be typed manually or dragged and dropped from a file manager. The script handles `~` expansion, quoted paths, and backslash-escaped spaces.

If the output file already exists, you will be prompted to overwrite it or choose a different name.
