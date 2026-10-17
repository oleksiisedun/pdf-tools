import sys
from pathlib import Path

# The tool scripts import sibling modules (ocr_common) because they run with
# tools/py as sys.path[0]; mirror that for the tests.
sys.path.insert(0, str(Path(__file__).parents[2] / "tools" / "py"))
