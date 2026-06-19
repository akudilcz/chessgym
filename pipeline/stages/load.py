"""
Stage 1–2: parse and normalize inputs into in-memory Puzzle records.

Inputs:
  - Lichess puzzle CSV (real or mock).
  - Classical studies PGN.
  - Famous positions JSON.

Outputs:
  - iterable of Puzzle dicts with a uniform shape.
"""
from __future__ import annotations

import csv
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

import chess


@dataclass
class Puzzle:
    id: str
    fen: str                      # position BEFORE setup move
    setup_move: str               # UCI; empty string when there is no setup move
    side_to_move: str             # 'w' or 'b' — AFTER setup move
    moves_uci: list[str]          # solver/opponent alternating, starting with solver
    themes: list[str]             # canonical theme ids
    lichess_themes: list[str]     # raw themes from CSV (for mapping)
    rating: int
    rating_dev: int
    popularity: int
    nb_plays: int
    origin_kind: str              # 'lichess' | 'study' | 'famous'
    origin_label: str | None
    explanation: str | None
    features: dict = field(default_factory=dict)   # filled by score stage
    interest: float = 0.0                          # filled by score stage


def _derive_displayed_board(fen: str, setup_uci: str) -> chess.Board:
    board = chess.Board(fen)
    if setup_uci:
        board.push_uci(setup_uci)
    return board


def load_lichess_csv(path: Path) -> Iterable[Puzzle]:
    """Read the Lichess puzzle CSV (mock or real) into Puzzle records."""
    with path.open() as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            moves = row["Moves"].split()
            if len(moves) < 2:
                # Lichess puzzles always have at least a setup + solver move.
                continue
            setup = moves[0]
            solver_and_rest = moves[1:]
            displayed = _derive_displayed_board(row["FEN"], setup)
            yield Puzzle(
                id=row["PuzzleId"],
                fen=row["FEN"],
                setup_move=setup,
                side_to_move="w" if displayed.turn == chess.WHITE else "b",
                moves_uci=solver_and_rest,
                themes=[],  # filled by themes stage
                lichess_themes=row["Themes"].split(),
                rating=int(row["Rating"]),
                rating_dev=int(row["RatingDeviation"]),
                popularity=int(row["Popularity"]),
                nb_plays=int(row["NbPlays"]),
                origin_kind="lichess",
                origin_label=None,
                explanation=None,
            )


def load_famous_json(path: Path) -> Iterable[Puzzle]:
    with path.open() as fh:
        items = json.load(fh)
    for it in items:
        setup = it.get("setup_move") or ""
        moves = it["solution_uci"].split()
        fen = it["fen"]
        # A Lichess row's first move is the opponent's blunder, replayed so
        # the player sees how the position arose. A famous study has no such
        # move: its first move IS the puzzle — Reti's Kg7, Lasker's queen
        # sacrifice, Saavedra's c8=R. Treating it as a setup move plays the
        # famous move for the player AND flips the sides, leaving them to
        # defend while the app performs the brilliancy. When no setup move is
        # declared, the board is shown exactly as the FEN states it.
        solver_and_rest = moves
        displayed = _derive_displayed_board(fen, setup)
        yield Puzzle(
            id=it["id"],
            fen=fen,
            setup_move=setup,
            side_to_move="w" if displayed.turn == chess.WHITE else "b",
            moves_uci=solver_and_rest,
            themes=it["themes"],          # already canonical
            lichess_themes=[],
            rating=it["rating"],
            rating_dev=it["rating_dev"],
            popularity=it["popularity"],
            nb_plays=it["nb_plays"],
            origin_kind=it["origin_kind"],
            origin_label=it["origin_label"],
            explanation=it.get("explanation"),
        )


def load_all(
    lichess_csv: Path | None,
    famous_json: Path | None,
) -> list[Puzzle]:
    out: list[Puzzle] = []
    if lichess_csv and lichess_csv.exists():
        out.extend(load_lichess_csv(lichess_csv))
    if famous_json and famous_json.exists():
        out.extend(load_famous_json(famous_json))
    return out
