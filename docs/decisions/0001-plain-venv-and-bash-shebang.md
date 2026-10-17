# 0001: Plain pip/venv, `#!/bin/bash`, and tests outside `check.sh`

## Context

The global conventions prefer `uv` with a committed `uv.lock` for Python and `#!/usr/bin/env bash` for shell. This repo is a set of interactive scripts run on whatever machine the user happens to be on, not a packaged project.

## Decision

- **Plain `pip`/`venv`, no `uv`, no `uv.lock`.** The tool venvs (`~/.pdf-signer-venv`, `~/.pdf-contrast-enhancer-venv`) are bootstrapped at runtime by `ensure_venv`, so assuming `uv` on the end user's machine isn't justified. `pyproject.toml` holds ruff/pyright config only. Dev-only linters are installed with plain `pip` too.
- **`#!/bin/bash`, not `#!/usr/bin/env bash`.** Enforced by `checks/conventions.sh`; the scripts are Linux-only (apt, `stat -c`), so there is no portability to gain.
- **pytest, bats unit and e2e suites are not part of `./check.sh`.** `check.sh` stays fast, offline and dependency-free so it can run after every edit. The suites need venvs, network on first run, or system tools (`gs`, `ffmpeg`, tesseract); `checks/python.sh` still lints and type-checks the test code.
- **`set +e`/`set -e` around piped commands** (compressor, contrast-enhancer, signer, print-marks) only toggles `errexit` so the exit code can be read from `PIPESTATUS[0]`; `-u` and `pipefail` stay on.

## Consequences

- No lockfile: venv package versions float to latest on each run (`pip install` runs every time to pick up updates).
- Agents should not "fix" the shebang or migrate to uv without revisiting this record.
