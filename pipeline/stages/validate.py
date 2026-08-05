"""
Validation: ensure every move in every puzzle's solution line is legal.

This catches data entry errors in famous_positions.json and any future
non-Lichess input source. Lichess's CSV is assumed legal but this check is
cheap, so we run it across everything.

Puzzles that fail validation are DROPPED and counted, never passed through
silently: a corpus that quietly ships an illegal line is worse than a smaller
one, and a discard that is not reported cannot be noticed.
"""
from __future__ import annotations

import sys

import chess

from .load import Puzzle


def validate(puzzles: list[Puzzle]) -> tuple[list[Puzzle], list[tuple[str, str]]]:
    """Return (kept, rejects) where rejects is [(id, reason), ...]."""
    kept: list[Puzzle] = []
    rejects: list[tuple[str, str]] = []
    for p in puzzles:
        reason = _validate_one(p)
        if reason is None:
            kept.append(p)
        else:
            rejects.append((p.id, reason))
    return kept, rejects


def _validate_one(p: Puzzle) -> str | None:
    try:
        board = chess.Board(p.fen)
    except ValueError as e:
        return f"invalid FEN: {e}"
    # chess.Board() only rejects FEN syntax; adjacent kings, a missing king
    # or an impossible check all parse fine. A typo'd famous position would
    # otherwise ship a board the app's dartchess layer may choke on.
    if not board.is_valid():
        return f"illegal position: {board.status()!r}"
    if p.setup_move:
        try:
            mv = chess.Move.from_uci(p.setup_move)
        except ValueError:
            return f"invalid setup UCI: {p.setup_move}"
        if mv not in board.legal_moves:
            return f"setup move not legal: {p.setup_move}"
        board.push(mv)
    for i, uci in enumerate(p.moves_uci):
        try:
            mv = chess.Move.from_uci(uci)
        except ValueError:
            return f"invalid UCI at ply {i}: {uci}"
        if mv not in board.legal_moves:
            return f"illegal move at ply {i}: {uci} in {board.fen()}"
        board.push(mv)
    return None


def report(rejects: list[tuple[str, str]], fh=sys.stderr) -> None:
    if not rejects:
        return
    print(f"WARNING: {len(rejects)} puzzles failed validation:", file=fh)
    for pid, reason in rejects[:20]:
        print(f"  {pid}: {reason}", file=fh)
    if len(rejects) > 20:
        print(f"  ... and {len(rejects) - 20} more", file=fh)
