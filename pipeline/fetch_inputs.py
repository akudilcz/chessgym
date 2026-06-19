"""
Download pipeline inputs.

Fetches the Lichess open puzzle database (CC0) from database.lichess.org and
decompresses a configurable number of rows. Use --rows 100000 for a dev
sample; use --rows all to capture everything (~3.5 GB uncompressed).

The file is written to pipeline/input/lichess_db_puzzle.csv. No hash check
or resume logic — this is a dev tool, not a production fetcher.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


CSV_URL = "https://database.lichess.org/lichess_db_puzzle.csv.zst"


def fetch(rows: int | None, out: Path) -> int:
    out.parent.mkdir(parents=True, exist_ok=True)
    curl = subprocess.Popen(
        ["curl", "-sLf", CSV_URL],
        stdout=subprocess.PIPE,
    )
    zstd = subprocess.Popen(
        ["zstdcat"],
        stdin=curl.stdout,
        stdout=subprocess.PIPE,
    )
    if curl.stdout is not None:
        curl.stdout.close()
    n_rows_written = 0
    limit = rows if rows is not None else None
    with out.open("w") as fh:
        assert zstd.stdout is not None
        for line in zstd.stdout:
            if limit is not None and n_rows_written > limit:
                break
            fh.write(line.decode())
            n_rows_written += 1
    zstd.terminate()
    curl.terminate()
    return n_rows_written


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--rows", default="100000",
                   help="number of CSV rows (header counts as 1), or 'all'")
    p.add_argument("--out", type=Path,
                   default=Path("pipeline/input/lichess_db_puzzle.csv"))
    args = p.parse_args()
    rows = None if args.rows == "all" else int(args.rows)
    n = fetch(rows, args.out)
    print(f"wrote {n} rows to {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
