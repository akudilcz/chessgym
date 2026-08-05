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
    truncated = False
    with out.open("w", encoding="utf-8") as fh:
        assert zstd.stdout is not None
        for line in zstd.stdout:
            if limit is not None and n_rows_written >= limit:
                truncated = True
                break
            fh.write(line.decode("utf-8"))
            n_rows_written += 1
    if truncated:
        # We abandoned the stream on purpose; kill both ends and reap them.
        zstd.terminate()
        curl.terminate()
        zstd.wait()
        curl.wait()
    else:
        # Stream ended by itself — a failed curl (404, network down) also
        # looks like this, so the exit codes are the only signal that the
        # file is silently empty/truncated rather than complete.
        zstd.wait()
        curl.wait()
        if curl.returncode != 0:
            raise RuntimeError(f"curl failed with exit code {curl.returncode}")
        if zstd.returncode != 0:
            raise RuntimeError(f"zstdcat failed with exit code {zstd.returncode}")
    return n_rows_written


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--rows", default="100000",
                   help="number of CSV rows (header counts as 1), or 'all'")
    p.add_argument("--out", type=Path,
                   default=Path("pipeline/input/lichess_db_puzzle.csv"))
    args = p.parse_args()
    rows = None if args.rows == "all" else int(args.rows)
    try:
        n = fetch(rows, args.out)
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    if n == 0:
        print("ERROR: no rows fetched", file=sys.stderr)
        return 1
    print(f"wrote {n} rows to {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
