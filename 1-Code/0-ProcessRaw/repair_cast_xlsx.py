"""
repair_cast_xlsx.py
Megan Harris (2026-10)

Why this exists
---------------
Some CAST report downloads (e.g. loads-per-unit-countyLoadsourceAgency.xlsx) store worksheet
cells WITHOUT cell addresses: rows are numbered (<x:row r="1">) but cells are written as
<x:c t="str"> with no r="A1" attribute. The Excel file format allows this (a reader should infer
each cell's column from its position), and Excel, openpyxl and pandas read these files fine.
Julia's XLSX.jl does not: it reads each cell's address and fails with
    XLSXError:  is not a valid CellRef.

What it does
------------
For every .xlsx in a CAST scenario folder, checks whether any worksheet has cells without
addresses. Files that do are read with pandas (all sheets, values unchanged) and re-written to
0-Data/2-IntermediateData as
    <original name>-<scenario without hyphens>-repaired.xlsx
e.g. loads-per-unit-countyLoadsourceAgency-2024progress-repaired.xlsx
Raw files are never modified. Files that already have addresses are skipped.

Usage (from the project folder that contains 0-Data and 1-Code, e.g. 2026-06-02a):
    python 1-Code/0-ProcessRaw/repair_cast_xlsx.py                 # scenario 2024-progress
    python 1-Code/0-ProcessRaw/repair_cast_xlsx.py 2023-progress   # another scenario folder
    python 1-Code/0-ProcessRaw/repair_cast_xlsx.py --check         # report only, write nothing
Requires: pandas, openpyxl
"""
import io
import re
import sys
import zipfile
from pathlib import Path

import pandas as pd

RAW_ROOT = Path("0-Data/1-RawData/1-ScenarioData").resolve()
OUT_DIR = Path("0-Data/2-IntermediateData").resolve()

CELL = re.compile(rb"<(?:\w+:)?c\b[^>]*>")
HAS_REF = re.compile(rb'\br="[A-Z]+[0-9]+"')


def cells_missing_refs(src) -> int:
    """Number of worksheet cells with no cell address (r attribute). src: path or file-like."""
    missing = 0
    with zipfile.ZipFile(src) as z:
        for name in z.namelist():
            if name.startswith("xl/worksheets/") and name.endswith(".xml"):
                for c in CELL.findall(z.read(name)):
                    if not HAS_REF.search(c):
                        missing += 1
    return missing


def repair(path: Path, out_path: Path) -> None:
    sheets = pd.read_excel(path, sheet_name=None)          # dict: sheet name -> DataFrame
    buf = io.BytesIO()
    with pd.ExcelWriter(buf, engine="openpyxl") as w:
        for name, df in sheets.items():
            df.to_excel(w, sheet_name=name, index=False)
    # verify in memory before writing: same sheets and shapes, every cell has an address
    buf.seek(0)
    back = pd.read_excel(buf, sheet_name=None)
    for name, df in sheets.items():
        assert back[name].shape == df.shape, f"{out_path.name}/{name}: shape changed"
    buf.seek(0)
    assert cells_missing_refs(buf) == 0, f"{out_path.name}: cells still missing addresses"
    out_path.write_bytes(buf.getvalue())


def main(argv):
    check_only = "--check" in argv
    args = [a for a in argv if not a.startswith("--")]
    scenario = args[0] if args else "2024-progress"
    folder = RAW_ROOT / scenario
    if not folder.is_dir():
        sys.exit(f"Scenario folder not found: {folder} (run from the folder that contains 0-Data)")
    tag = scenario.replace("-", "")

    files = sorted(p for p in folder.glob("*.xlsx") if not p.name.startswith(("~$", "._")))
    if not files:
        sys.exit(f"No .xlsx files in {folder}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for p in files:
        n = cells_missing_refs(p)
        if n == 0:
            print(f"OK        {p.name}")
            continue
        out = OUT_DIR / f"{p.stem}-{tag}-repaired.xlsx"
        if check_only:
            status = "repaired copy exists" if out.exists() else "no repaired copy yet"
            print(f"NEEDS FIX {p.name}  ({n:,} cells without addresses; {status})")
        else:
            repair(p, out)
            print(f"REPAIRED  {p.name}  ({n:,} cells without addresses) -> {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
